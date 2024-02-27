set shell := ["nu", "-c"]
set positional-arguments

export UNSTABLE := "true"
export UNSTABLE_LIB := "true"
export DEBUG := "true"

default:
  @just --list

lint:
  deadnix -f
  statix check

show-flake:
  nix flake show --allow-import-from-derivation

run-sancho:
  #!/usr/bin/env bash
  DATA_DIR=~/.local/share/cardano ENVIRONMENT=sanchonet SOCKET_PATH="./sancho-public/node.socket" nix run .#run-cardano-node

run-demo:
  #!/usr/bin/env bash
  echo stopping cardano-node
  just stop
  echo "cleaning state-demo..."
  if [ -d state-demo ]; then
    chmod -R +w state-demo
    rm -rf state-demo
  fi
  echo "generating state-demo config..."
  export DATA_DIR=state-demo
  export KEY_DIR="state-demo/envs/custom"
  export TESTNET_MAGIC=42
  export PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo
  export NUM_GENESIS_KEYS=3
  export POOL_NAMES="sancho1 sancho2 sancho3"
  export GENESIS_DIR="$DATA_DIR"
  export BULK_CREDS=state-demo/bulk-creds.json
  export PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo
  export STAKE_POOL_DIR=state-demo/stake-pools
  SECURITY_PARAM=8 SLOT_LENGTH=100 START_TIME=$(date --utc +"%Y-%m-%dT%H:%M:%SZ" --date " now + 30 seconds") nix run .#job-gen-custom-node-config
  export PAYMENT_ADDRESS=$(cardano-cli-ng address build --testnet-magic 42 --payment-verification-key-file "$PAYMENT_KEY".vkey)
  echo "generating stake pools credentials..."
  nix run .#job-create-stake-pool-keys
  (
    jq -r '.[]' < "$KEY_DIR"/delegate-keys/bulk.creds.bft.json
    jq -r '.[]' < "$STAKE_POOL_DIR"/no-deploy/bulk.creds.pools.json
  ) | jq -s > "$BULK_CREDS"
  cp "$STAKE_POOL_DIR"/no-deploy/*.skey "$STAKE_POOL_DIR"/deploy/*.vkey "$STAKE_POOL_DIR"
  echo "start cardano-node in the background. Run \"just stop\" to stop"
  NODE_CONFIG=state-demo/rundir/node-config.json NODE_TOPOLOGY=state-demo/rundir/topology.json SOCKET_PATH=./node.socket nohup nix run .#run-cardano-node & echo $! > cardano.pid &
  sleep 30
  echo "moving genesis utxo..."
  sleep 1
  BYRON_SIGNING_KEY="$KEY_DIR"/utxo-keys/shelley.000.skey ERA_CMD="alonzo" nix run .#job-move-genesis-utxo
  sleep 3
  echo "registering stake pools..."
  sleep 1
  POOL_RELAY=sanchonet.local POOL_RELAY_PORT=3001 ERA_CMD="alonzo" nix run .#job-register-stake-pools
  sleep 160
  echo "forking to babbage..."
  just sync-status
  MAJOR_VERSION=7 ERA_CMD="alonzo" nix run .#job-update-proposal-hard-fork
  sleep 160
  echo "forking to babbage (intra-era)..."
  just sync-status
  MAJOR_VERSION=8 ERA_CMD="babbage" nix run .#job-update-proposal-hard-fork
  sleep 160
  echo "forking to conway..."
  just sync-status
  MAJOR_VERSION=9 ERA_CMD="babbage" nix run .#job-update-proposal-hard-fork
  sleep 160
  just sync-status
  echo -e "\n\n"
  echo "In conway era..."
  echo -e "\n\n"
  just register-drep
  sleep 10
  just vote-cc
  sleep 160
  cardano-cli-ng conway query gov-state --testnet-magic 42|jq .enactState.committee

vote-constitution:
  #!/usr/bin/env bash
  export KEY_DIR="state-demo/envs/custom"
  echo "Checking Constitution Hash..."
  echo -e "\n\n"
  cardano-cli-ng conway query constitution --testnet-magic 42
  echo -e "\n\n"
  echo "Submitting change to constitution..."
  echo -e "\n\n"
  sleep 2
  ACTION=create-constitution GOV_ACTION_DEPOSIT=1000000000 ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo STAKE_KEY=state-demo/stake-pools/no-deploy/sancho1-owner-stake TESTNET_MAGIC=42 nix run .#job-submit-gov-action -- "--constitution-hash" "$(cardano-cli-ng conway governance hash anchor-data --text "We the people of Barataria abide by these statutes: 1. Flat Caps are permissible, but cowboy hats are the traditional atire")" "--constitution-url" "https://proposals.sancho.network/1"
  sleep 10
  echo -e "\n\n"
  echo "Voting Unanimous with dreps"
  echo -e "\n\n"
  sleep 5
  just submit-vote-drep $(cardano-cli-ng transaction txid --tx-body-file tx-create-constitution.txbody) 0 yes
  sleep 10
  echo "Voting Unanimous with CC"
  just submit-vote-cc $(cardano-cli-ng transaction txid --tx-body-file tx-create-constitution.txbody) 0 yes
  sleep 230
  echo "Checking Constitution Hash..."
  cardano-cli-ng conway query constitution --testnet-magic 42

vote-treasury:
  #!/usr/bin/env bash
  export KEY_DIR="state-demo/envs/custom"
  echo "Submitting treasury proposal..."
  echo -e "\n\n"
  sleep 2
  ACTION=create-treasury-withdrawal GOV_ACTION_DEPOSIT=1000000000 ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo STAKE_KEY=state-demo/stake-pools/no-deploy/sancho1-owner-stake TESTNET_MAGIC=42 nix run .#job-submit-gov-action -- --funds-receiving-stake-verification-key-file state-demo/dreps/stake-1.vkey --transfer 5000000
  STAKE_ADDRESS=$(cardano-cli-ng stake-address build --testnet-magic 42 --stake-verification-key-file state-demo/dreps/stake-1.vkey)
  sleep 10
  echo -e "\n\n"
  echo "Voting Unanimous with dreps"
  echo -e "\n\n"
  sleep 5
  just submit-vote-drep $(cardano-cli-ng transaction txid --tx-body-file tx-create-treasury-withdrawal.txbody) 0 yes
  sleep 5
  echo "Voting Unanimous with CC"
  just submit-vote-cc $(cardano-cli-ng transaction txid --tx-body-file tx-create-treasury-withdrawal.txbody) 0 yes
  sleep 230
  cardano-cli-ng conway query stake-address-info --testnet-magic 42 --address "$STAKE_ADDRESS"

check-stake-drep:
  #!/usr/bin/env bash
  export KEY_DIR="state-demo/envs/custom"
  STAKE=$(cardano-cli-ng stake-address build --stake-verification-key-file state-demo/dreps/stake-1.vkey --testnet-magic 42)
  cardano-cli-ng conway query stake-address-info --testnet-magic 42 --address "$STAKE"

vote-cc:
  #!/usr/bin/env bash
  export KEY_DIR="state-demo/envs/custom"
  echo "Authorizing new CC keypair..."
  CC_DIR=state-demo/cc INDEX=1 ERA_CMD="conway" nix run .#job-gen-keys-cc
  sleep 10
  echo "Submitting CC committee proposal..."
  echo -e "\n\n"
  sleep 10
  ACTION=update-committee GOV_ACTION_DEPOSIT=1000000000 ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo STAKE_KEY=state-demo/stake-pools/no-deploy/sancho1-owner-stake TESTNET_MAGIC=42 nix run .#job-submit-gov-action -- --add-cc-cold-verification-key-file state-demo/cc/cold-1.vkey --epoch 199 --quorum 0.51
  sleep 20
  echo -e "\n\n"
  echo "Voting Unanimous with dreps"
  echo -e "\n\n"
  just submit-vote-drep $(cardano-cli-ng transaction txid --tx-body-file tx-update-committee.txbody) 0 yes
  sleep 10
  just submit-vote-spo $(cardano-cli-ng transaction txid --tx-body-file tx-update-committee.txbody) 0 yes
  sleep 180
  CC_DIR=state-demo/cc INDEX=1 ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo TESTNET_MAGIC=42 nix run .#job-register-cc

vote-k:
  #!/usr/bin/env bash
  export KEY_DIR="state-demo/envs/custom"
  echo "Submitting k -> 1000..."
  echo -e "\n\n"
  echo "k: $(cardano-cli-ng conway query protocol-parameters --testnet-magic 42|jq .stakePoolTargetNum)"
  sleep 10
  ACTION=create-protocol-parameters-update GOV_ACTION_DEPOSIT=1000000000 ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo STAKE_KEY=state-demo/stake-pools/no-deploy/sancho1-owner-stake TESTNET_MAGIC=42 nix run .#job-submit-gov-action -- --number-of-pools 1000
  sleep 20
  echo -e "\n\n"
  echo "Voting Unanimous with dreps"
  echo -e "\n\n"
  just submit-vote-drep $(cardano-cli-ng transaction txid --tx-body-file tx-create-protocol-parameters-update.txbody) 0 yes
  sleep 10
  echo "Voting Unanimous with CC"
  just submit-vote-cc $(cardano-cli-ng transaction txid --tx-body-file tx-create-protocol-parameters-update.txbody) 0 yes
  sleep 230
  echo "k: $(cardano-cli-ng conway query protocol-parameters --testnet-magic 42|jq .stakePoolTargetNum)"

stop:
  #!/usr/bin/env bash
  if [ -f cardano.pid ]; then
    kill $(< cardano.pid)
    rm cardano.pid
  fi

start:
  #!/usr/bin/env bash
  export BULK_CREDS=state-demo/bulk-creds.json
  DATA_DIR=state-demo NODE_CONFIG=state-demo/rundir/node-config.json NODE_TOPOLOGY=state-demo/rundir/topology.json SOCKET_PATH=./node.socket nohup nix run .#run-cardano-node & echo $! > cardano.pid &

sync-status:
  cardano-cli-ng query tip --testnet-magic 42

query-rich-utxo:
  #!/usr/bin/env bash
  cardano-cli-ng query utxo --testnet-magic 42 --address $(cardano-cli address build --testnet-magic 42 --payment-verification-key-file "$KEY_DIR"/utxo-keys/rich-utxo.vkey)

query-gov-status:
  #!/usr/bin/env bash
  cardano-cli-ng query governance ...


submit-vote-spo actiontx actionid decision:
  #!/usr/bin/env bash
  export KEY_DIR="state-demo/envs/custom"
  export ACTION_TX_ID={{actiontx}}
  export ACTION_TX_INDEX={{actionid}}
  export DECISION={{decision}}
  ROLE=spo ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo VOTE_KEY=state-demo/stake-pools/no-deploy/sancho1-cold TESTNET_MAGIC=42 nix run .#job-submit-vote
  sleep 30
  ROLE=spo ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo VOTE_KEY=state-demo/stake-pools/no-deploy/sancho2-cold TESTNET_MAGIC=42 nix run .#job-submit-vote
  sleep 30
  ROLE=spo ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo VOTE_KEY=state-demo/stake-pools/no-deploy/sancho3-cold TESTNET_MAGIC=42 nix run .#job-submit-vote
  sleep 30

submit-vote-drep actiontx actionid decision:
  #!/usr/bin/env bash
  export KEY_DIR="state-demo/envs/custom"
  export ACTION_TX_ID={{actiontx}}
  export ACTION_TX_INDEX={{actionid}}
  export DECISION={{decision}}
  ROLE=drep ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo VOTE_KEY=state-demo/dreps/drep-1 TESTNET_MAGIC=42 nix run .#job-submit-vote
  sleep 30
  ROLE=drep ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo VOTE_KEY=state-demo/dreps/drep-2 TESTNET_MAGIC=42 nix run .#job-submit-vote
  sleep 30

submit-vote-cc actiontx actionid decision:
  #!/usr/bin/env bash
  export KEY_DIR="state-demo/envs/custom"
  export ACTION_TX_ID={{actiontx}}
  export ACTION_TX_INDEX={{actionid}}
  export DECISION={{decision}}
  ROLE=cc ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo VOTE_KEY=state-demo/cc/hot-1 TESTNET_MAGIC=42 nix run .#job-submit-vote
  sleep 30

register-drep:
  #!/usr/bin/env bash
  export KEY_DIR="state-demo/envs/custom"
  DREP_DIR=state-demo/dreps STAKE_DEPOSIT=2000000 DREP_DEPOSIT=2000000 VOTING_POWER=123456789 INDEX=1 POOL_KEY=state-demo/stake-pools/no-deploy/sancho1-cold ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo TESTNET_MAGIC=42 nix run .#job-register-drep
  sleep 30
  DREP_DIR=state-demo/dreps STAKE_DEPOSIT=2000000 DREP_DEPOSIT=2000000 VOTING_POWER=987654321 INDEX=2 POOL_KEY=state-demo/stake-pools/no-deploy/sancho2-cold ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo TESTNET_MAGIC=42 nix run .#job-register-drep

delegate-drep:
  #!/usr/bin/env bash
  export KEY_DIR="state-demo/envs/custom"
  DREP_KEY=state-demo/dreps/drep-1 STAKE_KEY=state-demo/stake-pools/sancho1-owner-stake POOL_KEY=state-demo/stake-pools/sp-1-cold ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo TESTNET_MAGIC=42 nix run .#job-delegate-drep
  sleep 30
  DREP_KEY=state-demo/dreps/drep-1 STAKE_KEY=state-demo/stake-pools/sancho2-owner-stake POOL_KEY=state-demo/stake-pools/sp-2-cold ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo TESTNET_MAGIC=42 nix run .#job-delegate-drep
  sleep 30
  DREP_KEY=state-demo/dreps/drep-1 STAKE_KEY=state-demo/stake-pools/sancho3-owner-stake POOL_KEY=state-demo/stake-pools/sp-3-cold ERA_CMD="conway" PAYMENT_KEY="$KEY_DIR"/utxo-keys/rich-utxo TESTNET_MAGIC=42 nix run .#job-delegate-drep

demo-drep:
  #!/usr/bin/env bash
  export KEY_DIR="state-demo/envs/custom"
  just submit-action
  ACTIONTX=$(cardano-cli-ng transaction txid --tx-file
