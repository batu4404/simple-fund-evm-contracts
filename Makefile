include .env

deploy-fund:
	forge script script/DeploySimpleFund.s.sol --rpc-url $(RPC_URL) --chain-id $(CHAIN_ID) --broadcast --slow
