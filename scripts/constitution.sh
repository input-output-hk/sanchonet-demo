#!/usr/bin/env bash

exec 2> >(while IFS= read -r line; do echo -e "\e[34m${line}\e[0m" >&2; done)

# Unofficial bash strict mode.
# See: http://redsymbol.net/articles/unofficial-bash-strict-mode/

set -euo pipefail

UNAME=$(uname -s) SED=
case $UNAME in
  Darwin )      SED="gsed";;
  Linux )       SED="sed";;
esac

sprocket() {
  if [ "$UNAME" == "Windows_NT" ]; then
    # Named pipes names on Windows must have the structure: "\\.\pipe\PipeName"
    # See https://docs.microsoft.com/en-us/windows/win32/ipc/pipe-names
    echo -n '\\.\pipe\'
    echo "$1" | sed 's|/|\\|g'
  else
    echo "$1"
  fi
}

set -x

CARDANO_CLI="${CARDANO_CLI:-cardano-cli}"
NETWORK_MAGIC=42
ROOT=example
DREP_DIR=example/dreps
UTXO_DIR=example/utxo-keys
POOL_DIR=example/pools
TRANSACTIONS_DIR=example/transactions

mkdir -p "$TRANSACTIONS_DIR"

echo "QUERY GOVERNANCE STATE"

$CARDANO_CLI conway governance query gov-state --testnet-magic ${NETWORK_MAGIC} \
| jq '{gov, ratify: .ratify | del(.pparams, .prevGovActionIds, .prevPParams)}'


echo "DOWNLOAD A PROPOSAL FILE, THIS IS WHERE WE EXPLAIN WHY THIS PROPOSAL IS RELEVANT"

wget https://tinyurl.com/3wrwb2as -O "${TRANSACTIONS_DIR}/proposal.txt"

echo "DOWNLOAD OUR SAMPLE CONSTITUTION FILE"

wget https://tinyurl.com/4xdkkjm3  -O "${TRANSACTIONS_DIR}/constitution.txt"

echo "CALCULATE THE HASH OURSELVES"

hash=$(b2sum -l 256 ${TRANSACTIONS_DIR}/constitution.txt | cut -d' ' -f1)
echo "$hash"


echo "QUERY THE CURRENT CONTSTITUTION HASH"

$CARDANO_CLI conway governance query constitution \
  --testnet-magic $NETWORK_MAGIC

echo "CREATE A PROPOSAL TO UPDATE THE CONSTITUTION"

$CARDANO_CLI conway governance action create-constitution \
  --testnet \
  --governance-action-deposit 0 \
  --stake-verification-key-file "${UTXO_DIR}/stake1.vkey" \
  --proposal-url "https://tinyurl.com/3wrwb2as" \
  --proposal-file ""${TRANSACTIONS_DIR}/proposal.txt"" \
  --constitution-url "https://tinyurl.com/4xdkkjm3"  \
  --constitution-file "${TRANSACTIONS_DIR}/constitution.txt" \
  --out-file "${TRANSACTIONS_DIR}/constitution.action"

cat "${TRANSACTIONS_DIR}/constitution.action"

echo "BUILD, SIGN AND SUBMIT THE CONSTITUTION"

$CARDANO_CLI conway transaction build \
  --testnet-magic $NETWORK_MAGIC \
  --tx-in "$(cardano-cli query utxo --address "$(cat "${UTXO_DIR}/payment1.addr")" --testnet-magic $NETWORK_MAGIC --out-file /dev/stdout | jq -r 'keys[0]')" \
  --change-address "$(cat ${UTXO_DIR}/payment1.addr)" \
  --proposal-file "${TRANSACTIONS_DIR}/constitution.action" \
  --witness-override 2 \
  --out-file "${TRANSACTIONS_DIR}/constitution-tx.raw"

$CARDANO_CLI conway transaction sign \
  --testnet-magic $NETWORK_MAGIC \
  --tx-body-file "${TRANSACTIONS_DIR}/constitution-tx.raw" \
  --signing-key-file "${UTXO_DIR}/payment1.skey" \
  --signing-key-file "${UTXO_DIR}/stake1.skey" \
  --out-file "${TRANSACTIONS_DIR}/constitution-tx.signed"

$CARDANO_CLI conway transaction submit \
  --testnet-magic $NETWORK_MAGIC \
  --tx-file "${TRANSACTIONS_DIR}/constitution-tx.signed"

sleep 3

IDIX="$(cardano-cli query ledger-state --testnet-magic 42 | jq -r '.stateBefore.esLState.utxoState.ppups.gov.curGovActionsState | keys[0]')"
ID="${IDIX%#*}"  # This removes everything from the last # to the end
IX="${IDIX##*#}"   # This removes everything up to and including $ID

echo "VOTE AS DREPS AND AS SPO"

### ----------––––––––
# DREP VOTES
### ----------––––––––

for i in {1..3}; do
  $CARDANO_CLI conway governance vote create \
    --yes \
    --governance-action-tx-id "${ID}" \
    --governance-action-index "${IX}" \
    --drep-verification-key-file "${DREP_DIR}/drep${i}.vkey" \
    --out-file "${TRANSACTIONS_DIR}/${ID}-drep${i}.vote"

  cat "${TRANSACTIONS_DIR}/${ID}-drep${i}.vote"

  $CARDANO_CLI conway transaction build \
    --testnet-magic $NETWORK_MAGIC \
    --tx-in "$(cardano-cli query utxo --address "$(cat "${UTXO_DIR}/payment1.addr")" --testnet-magic $NETWORK_MAGIC --out-file /dev/stdout | jq -r 'keys[0]')" \
    --change-address "$(cat ${UTXO_DIR}/payment1.addr)" \
    --vote-file "${TRANSACTIONS_DIR}/${ID}-drep${i}.vote" \
    --witness-override 2 \
    --out-file "${TRANSACTIONS_DIR}/${ID}-drep${i}-tx.raw"

  $CARDANO_CLI conway transaction sign \
    --testnet-magic $NETWORK_MAGIC \
    --tx-body-file "${TRANSACTIONS_DIR}/${ID}-drep${i}-tx.raw" \
    --signing-key-file "${UTXO_DIR}/payment1.skey" \
    --signing-key-file "${DREP_DIR}/drep${i}.skey" \
    --out-file "${TRANSACTIONS_DIR}/${ID}-drep${i}-tx.signed"

  $CARDANO_CLI conway transaction submit \
    --testnet-magic $NETWORK_MAGIC \
    --tx-file "${TRANSACTIONS_DIR}/${ID}-drep${i}-tx.signed"

  sleep 3

done

### ----------––––––––
# SPO VOTES
### ----------––––––––

for i in {1..3}; do
  $CARDANO_CLI conway governance vote create \
    --yes \
    --governance-action-tx-id "${ID}" \
    --governance-action-index "${IX}" \
    --cold-verification-key-file "${POOL_DIR}/cold${i}.vkey" \
    --out-file "${TRANSACTIONS_DIR}/${ID}-spo${i}.vote"

  cat "${TRANSACTIONS_DIR}/${ID}-spo${i}.vote"

  $CARDANO_CLI conway transaction build \
    --testnet-magic $NETWORK_MAGIC \
    --tx-in "$(cardano-cli query utxo --address "$(cat "${UTXO_DIR}/payment1.addr")" --testnet-magic $NETWORK_MAGIC --out-file /dev/stdout | jq -r 'keys[0]')" \
    --change-address "$(cat ${UTXO_DIR}/payment1.addr)" \
    --vote-file "${TRANSACTIONS_DIR}/${ID}-spo${i}.vote" \
    --witness-override 2 \
    --out-file "${TRANSACTIONS_DIR}/${ID}-spo${i}-tx.raw"

  $CARDANO_CLI conway transaction sign \
    --testnet-magic $NETWORK_MAGIC \
    --tx-body-file "${TRANSACTIONS_DIR}/${ID}-spo${i}-tx.raw" \
    --signing-key-file "${UTXO_DIR}/payment1.skey" \
    --signing-key-file "${POOL_DIR}/cold${i}.skey" \
    --out-file "${TRANSACTIONS_DIR}/${ID}-spo${i}-tx.signed"

  $CARDANO_CLI conway transaction submit \
    --testnet-magic $NETWORK_MAGIC \
    --tx-file "${TRANSACTIONS_DIR}/${ID}-spo${i}-tx.signed"

  sleep 5

done

expiresAfter=$(cardano-cli conway governance query gov-state --testnet-magic 42 | jq -r '.gov.curGovActionsState[].expiresAfter')
echo "VOTING DEADLINE: ${expiresAfter}"
echo "WAIT UNTIL VOTING DEADLINE"

check_epoch() {
  while true; do

  currentEpoch=$($CARDANO_CLI conway query tip --testnet-magic $NETWORK_MAGIC | jq .epoch)

    if [ "${currentEpoch}" -gt "${expiresAfter}" ]; then
      $CARDANO_CLI query constitution-hash --testnet-magic $NETWORK_MAGIC
      break
    else
      sleep 30  # Sleep when the epoch hasn't changed
    fi
  done
}

# Call the function to check the epoch
check_epoch
