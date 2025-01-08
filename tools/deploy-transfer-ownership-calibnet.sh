#!/usr/bin/env bash
set -euo pipefail

#####################################
# Environment variables & defaults  #
#####################################

: "${FIL_CALIBNET_RPC_URL:?FIL_CALIBNET_RPC_URL not set. Please export it and rerun.}"
: "${FIL_CALIBNET_PRIVATE_KEY:?FIL_CALIBNET_PRIVATE_KEY not set. Please export it and rerun.}"
: "${NEW_OWNER:?NEW_OWNER not set. Please export it and rerun.}"


CHAIN_ID="${CHAIN_ID:-314159}"
COMPILER_VERSION="${COMPILER_VERSION:-0.8.22}"

#####################################
# 1. Create INIT_DATA               #
#####################################
echo "Generating calldata for initialize(uint256) with argument 150 ..."
INIT_DATA=$(cast calldata "initialize(uint256)" 150)
echo "INIT_DATA = $INIT_DATA"
echo

#####################################
# 1. Get deployer address           #
#####################################
echo "Deriving deployer address from private key ..."
DEPLOYER_ADDRESS=$(cast wallet address "$FIL_CALIBNET_PRIVATE_KEY")
echo "Deployer address: $DEPLOYER_ADDRESS"
echo

#####################################
# 2. Deploy PDPVerifier contract    #
#####################################
echo "Deploying PDPVerifier contract ..."
DEPLOY_OUTPUT_VERIFIER=$(
  forge create \
    --rpc-url "$FIL_CALIBNET_RPC_URL" \
    --private-key "$FIL_CALIBNET_PRIVATE_KEY" \
    --chain-id "$CHAIN_ID" \
    --compiler-version "$COMPILER_VERSION" \
    --json \
    src/PDPVerifier.sol:PDPVerifier
)

# Extract the deployed address from JSON output
PDP_VERIFIER_ADDRESS=$(echo "$DEPLOY_OUTPUT_VERIFIER" | jq -r '.deployedTo')
echo "PDPVerifier deployed at: $PDP_VERIFIER_ADDRESS"
echo

#####################################
# 3. Deploy Proxy contract          #
#####################################
echo "Deploying Proxy contract (MyERC1967Proxy) ..."
DEPLOY_OUTPUT_PROXY=$(
  forge create \
    --rpc-url "$FIL_CALIBNET_RPC_URL" \
    --private-key "$FIL_CALIBNET_PRIVATE_KEY" \
    --chain-id "$CHAIN_ID" \
    --compiler-version "$COMPILER_VERSION" \
    --constructor-args "$PDP_VERIFIER_ADDRESS" "$INIT_DATA" \
    --json \
    src/ERC1967Proxy.sol:MyERC1967Proxy
)

# Extract the deployed proxy address
PROXY_ADDRESS=$(echo "$DEPLOY_OUTPUT_PROXY" | jq -r '.deployedTo')
echo "Proxy deployed at: $PROXY_ADDRESS"
echo

#####################################
# 4. Check owner of proxy           #
#####################################
echo "Querying the proxy's owner ..."
OWNER_ADDRESS=$(
  cast call \
    --rpc-url "$FIL_CALIBNET_RPC_URL" \
    "$PROXY_ADDRESS" \
    "owner()(address)"
)
echo "Proxy owner: $OWNER_ADDRESS"

# Add validation check
if [ "${OWNER_ADDRESS,,}" != "${DEPLOYER_ADDRESS,,}" ]; then
    echo "failed to validate owner address"
    echo "Expected owner to be: ${DEPLOYER_ADDRESS}"
    echo "Got: ${OWNER_ADDRESS}"
    exit 1
fi
echo "✓ Owner address validated successfully"
echo

#####################################
# 5. Check implementation address    #
#####################################
# The storage slot for ERC1967 implementation:
IMPLEMENTATION_SLOT="0x360894A13BA1A3210667C828492DB98DCA3E2076CC3735A920A3CA505D382BBC"

echo "Checking proxy's implementation address from storage slot $IMPLEMENTATION_SLOT ..."
IMPLEMENTATION_ADDRESS=$(
  cast storage \
    --rpc-url "$FIL_CALIBNET_RPC_URL" \
    "$PROXY_ADDRESS" \
    "$IMPLEMENTATION_SLOT"
)
echo "Implementation address in Proxy: $IMPLEMENTATION_ADDRESS"
echo


#####################################
# Summary                           #
#####################################
echo "========== DEPLOYMENT SUMMARY =========="
echo "PDPVerifier Address:          $PDP_VERIFIER_ADDRESS"
echo "Proxy Address:                $PROXY_ADDRESS"
echo "Proxy Owner (should match deployer):  $OWNER_ADDRESS"
echo "PDPVerifier Implementation (via Proxy): $IMPLEMENTATION_ADDRESS"
echo "========================================"


#####################################
# 6. Transfer ownership            #
#####################################
echo
echo "Transferring ownership to new owner..."

cast send \
  --rpc-url "$FIL_CALIBNET_RPC_URL" \
  --private-key "$FIL_CALIBNET_PRIVATE_KEY" \
  --chain-id "$CHAIN_ID" \
  "$PROXY_ADDRESS" \
  "transferOwnership(address)" \
  "$NEW_OWNER"

echo "✓ Ownership transfer transaction submitted"

# Verify the ownership transfer
echo "Verifying new owner..."
NEW_OWNER_ADDRESS=$(
  cast call \
    --rpc-url "$FIL_CALIBNET_RPC_URL" \
    "$PROXY_ADDRESS" \
    "owner()(address)"
)

if [ "${NEW_OWNER_ADDRESS,,}" != "${NEW_OWNER,,}" ]; then
    echo "failed to transfer ownership"
    echo "Expected new owner to be: ${NEW_OWNER}"
    echo "Got: ${NEW_OWNER_ADDRESS}"
    exit 1
fi

echo "✓ Ownership transferred successfully to ${NEW_OWNER}"
echo
