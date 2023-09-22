set shell := ["nu", "-c"]
set positional-arguments

default:
  @just --list

lint:
  deadnix -f
  statix check

show-flake:
  nix flake show --allow-import-from-derivation

run-sancho:
  #!/usr/bin/env bash
  DEBUG=true DATA_DIR=~/.local/share/cardano ENVIRONMENT=sanchonet SOCKET_PATH="$CARDANO_NODE_SOCKET_PATH" nix run .#run-cardano-node

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
  export GENESIS_DIR=state-demo
  export DATA_DIR=state-demo/rundir
  export KEY_DIR=state-demo/envs/custom
  export TESTNET_MAGIC=42
  export PAYMENT_KEY=state-demo/utxo-keys/rich-utxo
  export NUM_GENESIS_KEYS=3
  export POOL_NAMES="sp-1 sp-2 sp-3"
  export STAKE_POOL_DIR=state-demo/groups/stake-pools
  export BULK_CREDS=state-demo/bulk-creds.all.json
  export PAYMENT_KEY=state-demo/envs/custom/utxo-keys/rich-utxo
  export UNSTABLE_LIB=true

  SECURITY_PARAM=8 SLOT_LENGTH=200 START_TIME=$(date --utc +"%Y-%m-%dT%H:%M:%SZ" --date " now + 30 seconds") nix run .#job-gen-custom-node-config
  echo "generating stake pools credentials..."
  nix run .#job-create-stake-pool-keys

  (
    jq -r '.[]' < "$KEY_DIR"/delegate-keys/bulk.creds.bft.json
    jq -r '.[]' < "$STAKE_POOL_DIR"/no-deploy/bulk.creds.pools.json
  ) | jq -s > "$BULK_CREDS"
  echo "start cardano-node in the background. Run \"just stop\" to stop"
  NODE_CONFIG=state-demo/rundir/node-config.json NODE_TOPOLOGY=state-demo/rundir/topology.json SOCKET_PATH=./node.socket nohup nix run .#run-cardano-node & echo $! > cardano.pid &
  echo "Sleeping 30 seconds until $(date -d  @$(($(date +%s) + 30)))"
  sleep 30

  echo "moving genesis utxo..."
  sleep 2
  BYRON_SIGNING_KEY="$KEY_DIR"/utxo-keys/shelley.000.skey ERA="--alonzo-era" nix run .#job-move-genesis-utxo
  sleep 7

  echo "registering stake pools..."
  sleep 2
  POOL_RELAY=sanchonet.local POOL_RELAY_PORT=3001 ERA="--alonzo-era" DEBUG=true nix run .#job-register-stake-pools

  echo "Sleeping 320 seconds until $(date -d  @$(($(date +%s) + 320)))"
  sleep 320
  echo "forking to babbage..."
  just sync-status
  MAJOR_VERSION=7 ERA="--alonzo-era" nix run .#job-update-proposal-hard-fork

  echo "Sleeping 320 seconds until $(date -d  @$(($(date +%s) + 320)))"
  sleep 320
  echo "forking to babbage (intra-era)..."
  just sync-status
  MAJOR_VERSION=8 ERA="--babbage-era" DEBUG=true nix run .#job-update-proposal-hard-fork

  echo "Sleeping 320 seconds until $(date -d  @$(($(date +%s) + 320)))"
  sleep 320
  echo "forking to conway..."
  just sync-status
  MAJOR_VERSION=9 ERA="--babbage-era" nix run .#job-update-proposal-hard-fork

  echo "Sleeping 320 seconds until $(date -d  @$(($(date +%s) + 320)))"
  sleep 320
  just sync-status
  echo -e "\n\n"
  echo "In conway era..."
  echo -e "\n\n"

demo-vote:
  #!/usr/bin/env bash
  echo "Checking Constitution Hash..."
  echo -e "\n\n"
  cardano-cli query constitution-hash --testnet-magic 42
  echo -e "\n\n"
  echo "Submitting change to constitution..."
  echo -e "\n\n"
  sleep 5
  just submit-action
  sleep 20
  echo -e "\n\n"
  echo "Voting unanimous yes with SPOs"
  echo -e "\n\n"
  sleep 5
  just submit-vote-spo $(cardano-cli transaction txid --tx-file tx-create-constitution.txsigned) 0 yes
  sleep 700
  echo -e "\n\n"
  echo "Checking Constitution Hash..."
  echo -e "\n\n"
  sleep 5
  cardano-cli query constitution-hash --testnet-magic 42
  sleep 20
  echo -e "\n\n"
  echo "Registering 2 dreps"
  echo -e "\n\n"
  sleep 5
  just register-drep
  sleep 320
  echo -e "\n\n"
  echo "Voting Unanimous with dreps"
  echo -e "\n\n"
  sleep 5
  just submit-vote-drep $(cardano-cli transaction txid --tx-file tx-create-constitution.txsigned) 0 yes
  sleep 700
  echo "Checking Constitution Hash..."
  cardano-cli query constitution-hash --testnet-magic 42


stop:
  #!/usr/bin/env bash
  if [ -f cardano.pid ]; then
    kill $(< cardano.pid)
    rm cardano.pid
  fi

start:
  #!/usr/bin/env bash
  export BULK_CREDS=state-demo/bulk-creds.json
  DATA_DIR=state-demo/rundir NODE_CONFIG=state-demo/rundir/node-config.json NODE_TOPOLOGY=state-demo/rundir/topology.json SOCKET_PATH=./node.socket nohup nix run .#run-cardano-node & echo $! > cardano.pid &

sync-status:
  cardano-cli query tip --testnet-magic 42

query-rich-utxo:
  #!/usr/bin/env bash
  cardano-cli query utxo --testnet-magic 42 --address $(cardano-cli address build --testnet-magic 42 --payment-verification-key-file state-demo/envs/custom/utxo-keys/rich-utxo.vkey)

query-gov-status:
  #!/usr/bin/env bash
  cardano-cli query governance ...

submit-action:
  #!/usr/bin/env bash
  ACTION=create-constitution GOV_ACTION_DEPOSIT=10000000 ERA="--conway-era" PAYMENT_KEY=state-demo/envs/custom/utxo-keys/rich-utxo STAKE_KEY=state-demo/groups/stake-pools/no-deploy/sp-1-owner-stake TESTNET_MAGIC=42 DEBUG=true nix run .#job-submit-gov-action

submit-vote-spo actiontx actionid decision:
  #!/usr/bin/env bash
  export ACTION_TX_ID={{actiontx}}
  export ACTION_TX_INDEX={{actionid}}
  export DECISION={{decision}}
  ROLE=spo ERA="--conway-era" PAYMENT_KEY=state-demo/envs/custom/utxo-keys/rich-utxo VOTE_KEY=state-demo/groups/stake-pools/no-deploy/sp-1-cold TESTNET_MAGIC=42 DEBUG=true nix run .#job-submit-vote
  sleep 30
  ROLE=spo ERA="--conway-era" PAYMENT_KEY=state-demo/envs/custom/utxo-keys/rich-utxo VOTE_KEY=state-demo/groups/stake-pools/no-deploy/sp-2-cold TESTNET_MAGIC=42 DEBUG=true nix run .#job-submit-vote
  sleep 30
  ROLE=spo ERA="--conway-era" PAYMENT_KEY=state-demo/envs/custom/utxo-keys/rich-utxo VOTE_KEY=state-demo/groups/stake-pools/no-deploy/sp-3-cold TESTNET_MAGIC=42 DEBUG=true nix run .#job-submit-vote
  sleep 30

submit-vote-drep actiontx actionid decision:
  #!/usr/bin/env bash
  export ACTION_TX_ID={{actiontx}}
  export ACTION_TX_INDEX={{actionid}}
  export DECISION={{decision}}
  ROLE=drep ERA="--conway-era" PAYMENT_KEY=state-demo/envs/custom/utxo-keys/rich-utxo VOTE_KEY=state-demo/dreps/drep-1 TESTNET_MAGIC=42 DEBUG=true nix run .#job-submit-vote
  sleep 30
  ROLE=drep ERA="--conway-era" PAYMENT_KEY=state-demo/envs/custom/utxo-keys/rich-utxo VOTE_KEY=state-demo/dreps/drep-2 TESTNET_MAGIC=42 DEBUG=true nix run .#job-submit-vote
  sleep 30

register-drep:
  #!/usr/bin/env bash
  DREP_DIR=state-demo/dreps VOTING_POWER=123456789 INDEX=1 POOL_KEY=state-demo/groups/stake-pools/no-deploy/sp-1-cold ERA="--conway-era" PAYMENT_KEY=state-demo/envs/custom/utxo-keys/rich-utxo TESTNET_MAGIC=42 DEBUG=true nix run .#job-register-drep
  sleep 30
  DREP_DIR=state-demo/dreps VOTING_POWER=987654321 INDEX=2 POOL_KEY=state-demo/groups/stake-pools/no-deploy/sp-2-cold ERA="--conway-era" PAYMENT_KEY=state-demo/envs/custom/utxo-keys/rich-utxo TESTNET_MAGIC=42 DEBUG=true nix run .#job-register-drep

delegate-drep:
  #!/usr/bin/env bash
  DREP_KEY=state-demo/dreps/drep-1 STAKE_KEY=state-demo/groups/stake-pools/no-deploy/sp-1-owner-stake POOL_KEY=state-demo/groups/stake-pools/no-deploy/sp-1-cold ERA="--conway-era" PAYMENT_KEY=state-demo/envs/custom/utxo-keys/rich-utxo TESTNET_MAGIC=42 DEBUG=true nix run .#job-delegate-drep
  sleep 30
  DREP_KEY=state-demo/dreps/drep-1 STAKE_KEY=state-demo/groups/stake-pools/no-deploy/sp-2-owner-stake POOL_KEY=state-demo/groups/stake-pools/no-deploy/sp-2-cold ERA="--conway-era" PAYMENT_KEY=state-demo/envs/custom/utxo-keys/rich-utxo TESTNET_MAGIC=42 DEBUG=true nix run .#job-delegate-drep
  sleep 30
  DREP_KEY=state-demo/dreps/drep-1 STAKE_KEY=state-demo/groups/stake-pools/no-deploy/sp-3-owner-stake POOL_KEY=state-demo/groups/stake-pools/no-deploy/sp-3-cold ERA="--conway-era" PAYMENT_KEY=state-demo/envs/custom/utxo-keys/rich-utxo TESTNET_MAGIC=42 DEBUG=true nix run .#job-delegate-drep

demo-drep:
  #!/usr/bin/env bash
  just submit-action
  ACTIONTX=$(cardano-cli transaction txid --tx-file
