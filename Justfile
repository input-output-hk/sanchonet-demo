set shell := ["nu", "-c"]
set positional-arguments

default:
  @just --list

lint:
  deadnix -f
  statix check

show-flake:
  nix flake show --allow-import-from-derivation

run:
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
  export KEY_DIR=state-demo
  export TESTNET_MAGIC=42
  export PAYMENT_KEY=state-demo/utxo-keys/rich-utxo
  export NUM_GENESIS_KEYS=3
  export NUM_POOLS=3
  export START_INDEX=1
  export END_INDEX=3
  export GENESIS_DIR="$DATA_DIR"
  export BULK_CREDS=state-demo/bulk-creds.json
  export PAYMENT_KEY=state-demo/utxo-keys/rich-utxo
  export STAKE_POOL_DIR=state-demo/stake-pools
  SECURITY_PARAM=8 SLOT_LENGTH=200 START_TIME=$(date --utc +"%Y-%m-%dT%H:%M:%SZ" --date " now + 30 seconds") nix run .#job-gen-custom-node-config
  export PAYMENT_ADDRESS=$(cardano-cli address build --testnet-magic 42 --payment-verification-key-file "$PAYMENT_KEY".vkey)
  nix run .#job-create-stake-pool-keys
  cat state-demo/delegate-keys/bulk.creds.bft.json state-demo/stake-pools/bulk.creds.pools.json|jq -s > "$BULK_CREDS"
  echo "start cardano-node in the background. Run \"just stop\" to stop"
  NODE_CONFIG=state-demo/node-config.json NODE_TOPOLOGY=state-demo/topology.json SOCKET_PATH=./node.socket nohup nix run .#run-cardano-node & echo $! > cardano.pid &
  sleep 30
  echo "moving genesis utxo..."
  BYRON_SIGNING_KEY=state-demo/utxo-keys/shelley.000.skey ERA="--alonzo-era" nix run .#job-move-genesis-utxo
  sleep 7
  echo "registering stake pools..."
  POOL_RELAY=sanchonet.local POOL_RELAY_PORT=3001 ERA="--alonzo-era" nix run .#job-register-stake-pools
  sleep 320
  echo "forking to babbage..."
  just sync-status
  MAJOR_VERSION=7 ERA="--alonzo-era" nix run .#job-update-proposal-hard-fork
  sleep 320
  echo "forking to babbage (intra-era)..."
  just sync-status
  MAJOR_VERSION=8 ERA="--babbage-era" nix run .#job-update-proposal-hard-fork
  sleep 320
  echo "forking to conway..."
  just sync-status
  MAJOR_VERSION=9 ERA="--babbage-era" nix run .#job-update-proposal-hard-fork
  sleep 320
  just sync-status

stop:
  #!/usr/bin/env bash
  if [ -f cardano.pid ]; then
    kill $(< cardano.pid)
    rm cardano.pid
  fi

sync-status:
  cardano-cli query tip --testnet-magic 42

query-rich-utxo:
  #!/usr/bin/env bash
  cardano-cli query utxo --testnet-magic 42 --address $(cardano-cli address build --testnet-magic 42 --payment-verification-key-file state-demo/utxo-keys/rich-utxo.vkey)

query-gov-status:
  #!/usr/bin/env bash
  cardano-cli query governance ...
