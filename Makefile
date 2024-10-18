# Makefile for PDP Contracts

# Variables
RPC_URL ?= 
KEYSTORE_PATH ?= 
PASSWORD ?= 
CHALLENGE_FINALITY ?= 

# Targets
build:
	cd contracts && forge build

test:
	cd contracts && forge test -vv

deploy-calibnet:
	cd contracts && ../tools/deploy-calibnet.sh

deploy-devnet:
	cd contracts && ../tools/deploy-devnet.sh

testBurnFee:
	cd tools && ./testBurnFee.sh