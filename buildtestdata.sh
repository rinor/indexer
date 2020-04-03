#!/bin/bash
# requires a python3 environment with "py-algorand-sdk" installed
set -x
set -e

if [ -z "${GOALGORAND}" ]; then
    GOALGORAND="${GOPATH}/src/github.com/algorand/go-algorand"
fi

if [ -z "${E2EDATA}" ]; then
    E2EDATA="${HOME}/Algorand/e2edata"
fi

rm -rf "${E2EDATA}"
mkdir -p "${E2EDATA}"
(cd "${GOALGORAND}/test/scripts" && TEMPDIR="${E2EDATA}" python3 e2e_client_runner.py --keep-temps e2e_subs/*.sh)

LASTDATAROUND=$(sqlite3 "${E2EDATA}"/net/Primary/*/ledger.block.sqlite "SELECT max(rnd) FROM blocks")

echo $LASTDATAROUND

goal network start -r "${E2EDATA}"/net

mkdir -p "${E2EDATA}/blocks"
mkdir -p "${E2EDATA}/blocktars"

python3 ./blockarchiver.py --algod "${E2EDATA}"/net/Primary --blockdir "${E2EDATA}/blocks" --tardir "${E2EDATA}/blocktars" &
BLOCKARCHIVERPID=$!

ACCTROUND=$(sqlite3 "${E2EDATA}"/net/Primary/*/ledger.tracker.sqlite "SELECT rnd FROM acctrounds WHERE id = 'acctbase'")

while [ ${ACCTROUND} -lt ${LASTDATAROUND} ]; do
    sleep 4
    #goal node status -d "${E2EDATA}"/net/Primary|grep 'Last committed block: '
    ACCTROUND=$(sqlite3 "${E2EDATA}"/net/Primary/*/ledger.tracker.sqlite "SELECT rnd FROM acctrounds WHERE id = 'acctbase'")
done

goal network stop -r "${E2EDATA}"/net

kill $BLOCKARCHIVERPID

mkdir -p "${E2EDATA}/algod/tbd-v1/"
sqlite3 "${E2EDATA}"/net/Primary/*/ledger.tracker.sqlite ".backup '${E2EDATA}/algod/tbd-v1/ledger.tracker.sqlite'"
cp -p "${E2EDATA}/net/Primary/genesis.json" "${E2EDATA}/algod/genesis.json"

python3 ./blockarchiver.py --just-tar-blocks --blockdir "${E2EDATA}/blocks" --tardir "${E2EDATA}/blocktars"

PDIR=$(dirname "${E2EDATA}")
EDIR=$(basename "${E2EDATA}")
(cd "${PDIR}" && tar jcf "${E2EDATA}/e2edata.tar.bz2" "${EDIR}/blocktars" "${EDIR}/algod")
ls -l "${E2EDATA}/e2edata.tar.bz2"
