include .env

deploy-fund:
	forge script script/DeploySimpleFund.s.sol --rpc-url $(RPC_URL) --chain-id $(CHAIN_ID) --broadcast --slow

merkle-tree:
	FUND=$(FUND) AAVE_DECODER=$(AAVE_DECODER) NEST_DECODER=$(NEST_DECODER) LIGHTER_DECODER=$(LIGHTER_DECODER) \
		forge script script/CreateMerkleRoot.s.sol --rpc-url $(RPC_URL) --chain-id $(CHAIN_ID)
