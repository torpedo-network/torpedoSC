from brownie import accounts, TorpedoFactory, network, exceptions, TorpedoSession
from scripts.helpers import get_account, LOCAL_BLOCKCHAIN_ENVIRONMENTS
from scripts.deploy import deploy_TorpedoFactory
import pytest
from time import sleep

ETH_AMOUNT = 1
WEI_TO_ETH = 1000000000000000000


def test_price_feed():

    torpedo_factory = deploy_TorpedoFactory()

    usd = torpedo_factory.EthToUSD(ETH_AMOUNT)
    wei = torpedo_factory.USDToWei(usd)
    reproduced_eth = wei / WEI_TO_ETH

    # Relies on the fact that Eth volatility is less than $2 within
    # deployment of the two functions
    assert ETH_AMOUNT - reproduced_eth < 0.001


def test_add_phaestus():

    if network.show_active() not in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        pytest.skip("only for local testing")

    torpedo_factory = deploy_TorpedoFactory()
    phaestus_account_1 = get_account(index=1)
    phaestus_account_2 = get_account(index=2)

    now = torpedo_factory.getNow()

    # Requires at least 1 CPUs
    with pytest.raises(exceptions.VirtualMachineError):
        torpedo_factory.registerPhaestus(
            0, 1, now + 3600 * 8, 100, 1, 0, 20, 12, {"from": phaestus_account_1}
        )

    # Requires time to be at least 4 hours
    with pytest.raises(exceptions.VirtualMachineError):
        torpedo_factory.registerPhaestus(
            1, 1, now, 1000, 1, 0, 20, 12, {"from": phaestus_account_1}
        )

    torpedo_factory.registerPhaestus(
        2, 1, now + 3600 * 8, 100, 1, 0, 20, 12, {"from": phaestus_account_1}
    )
    torpedo_factory.registerPhaestus(
        4, 4, now + 3600 * 5, 1000, 1, 0, 20, 12, {"from": phaestus_account_2}
    )

    # Only 2 successful additions to phaestusNodes, this length should be 2 (zero indexed)
    with pytest.raises(exceptions.VirtualMachineError):
        p = torpedo_factory.viewPhaestus(2)


def test_find_best_phaestus():
    torpedo_factory = deploy_TorpedoFactory()
    phaestus_account_1 = get_account(index=1)
    phaestus_account_2 = get_account(index=2)
    phaestus_account_3 = get_account(index=3)

    now = torpedo_factory.getNow()

    torpedo_factory.registerPhaestus(
        2, 1, now + 3600 * 8, 1, 1, 0, 20, 12, {"from": phaestus_account_1}
    )
    torpedo_factory.registerPhaestus(
        4, 4, now + 3600 * 5, 100, 1, 0, 20, 12, {"from": phaestus_account_2}
    )

    torpedo_factory.registerPhaestus(
        4, 1, now + 3600 * 8, 21, 1, 0, 20, 12, {"from": phaestus_account_3}
    )
    torpedo_factory.registerPhaestus(
        4, 4, now + 3600 * 16, 1000, 1, 0, 20, 12, {"from": phaestus_account_1}
    )

    price = torpedo_factory.calculateUSDCost([3, 1, 2, 1, 0, 10, 2])
    expected_price = 42

    assert price == expected_price


def test_start_session():

    torpedo_factory = deploy_TorpedoFactory()
    client_account_1 = get_account(index=1)
    phaestus_account_1 = get_account(index=2)

    now = torpedo_factory.getNow()
    torpedo_factory.registerPhaestus(
        2, 1, now + 4 * 3600, 1, 1, 0, 20, 12, {"from": phaestus_account_1}
    )
    torpedo_factory.registerPhaestus(
        2, 1, now + 4 * 3600, 1, 1, 0, 20, 12, {"from": phaestus_account_1}
    )
    torpedo_factory.registerPhaestus(
        2, 1, now + 4 * 3600, 100, 1, 0, 20, 12, {"from": phaestus_account_1}
    )
    torpedo_factory.registerPhaestus(
        2, 1, now + 4 * 3600, 1, 1, 0, 20, 12, {"from": phaestus_account_1}
    )

    address = torpedo_factory.createSession(
        [2, 1, 1, 1, 0, 10, 2],
        {"from": client_account_1, "value": 2 * WEI_TO_ETH},
    )

    session = TorpedoSession.at(address.return_value)

    assert (
        session.getClientAddress.call({"from": torpedo_factory.address})
        == client_account_1
    )


def test_get_pool_tvl():
    torpedo_factory = deploy_TorpedoFactory()
    client_account_1 = get_account(index=1)
    phaestus_account_1 = get_account(index=2)

    now = torpedo_factory.getNow()
    checkTime = 11
    checkCPU = 6
    checkGPU = 2
    checkDiskSpace = 40
    checkRAM = 24
    torpedo_factory.registerPhaestus(
        2, 1, now + 4 * 3600, 1, 1, 0, 20, 12, {"from": phaestus_account_1}
    )
    torpedo_factory.registerPhaestus(
        4, 1, now + 8 * 3600, 1, 1, 0, 20, 12, {"from": phaestus_account_1}
    )

    maxCPUs, maxGPUs, maxTime, maxDiskSpace, maxRam = torpedo_factory.getPoolTVL()
    sleep(1)
    assert maxCPUs == checkCPU
    assert maxGPUs == checkGPU
    assert maxDiskSpace == checkDiskSpace
    assert maxRam == checkRAM
    assert maxTime >= checkTime

    # empty phaestus check
    # usd call without conditions met...


def test_phaestus_active():
    torpedo_factory = deploy_TorpedoFactory()
    client_account_1 = get_account(index=1)
    phaestus_account_1 = get_account(index=2)

    now = torpedo_factory.getNow()

    torpedo_factory.registerPhaestus(
        2, 1, now + 4 * 3600, 1, 1, 0, 20, 12, {"from": phaestus_account_1}
    )

    status = torpedo_factory.checkStatusOfPhaestus({"from": phaestus_account_1})
    assert status == False

    # Create a session
    address = torpedo_factory.createSession(
        [2, 1, 1, 1, 0, 10, 2],
        {"from": client_account_1, "value": 2 * WEI_TO_ETH},
    )
    session = TorpedoSession.at(address.return_value)

    # Now that the session is created, the status of phaestus should have toggled to engaged.
    status = torpedo_factory.checkStatusOfPhaestus({"from": phaestus_account_1})
    assert status == True

    # Check that phaestus node gets the right session address
    sessionAddress = torpedo_factory.getSessionAddress({"from": phaestus_account_1})
    assert session == sessionAddress
