from brownie import accounts, TorpedoFactory, network, exceptions, TorpedoSession
from scripts.helpers import get_account, LOCAL_BLOCKCHAIN_ENVIRONMENTS
from scripts.deploy import deploy_TorpedoFactory, deploy_session
import pytest

ETH_AMOUNT = 1
WEI_TO_ETH = 1000000000000000000


def test_owner_of_session():
    torpedo_factory = deploy_TorpedoFactory()
    torpedo_session_address = deploy_session(torpedo_factory)
    torpedo_session = TorpedoSession.at(torpedo_session_address)

    client_account_1 = get_account(index=1)

    assert torpedo_session.owner.call() == client_account_1


def test_initialise_and_start_session():
    torpedo_factory = deploy_TorpedoFactory()
    torpedo_session_address = deploy_session(torpedo_factory)
    torpedo_session = TorpedoSession.at(torpedo_session_address)

    client_account_1 = get_account(index=1)
    phaestus_account_1 = get_account(index=2)

    expected_url = "https://torpedo.one/phaestus-node-42/"
    expected_password = "boogie"

    torpedo_session.initialiseSession(
        expected_url, expected_password, {"from": phaestus_account_1}
    )

    txn = torpedo_session.startSession({"from": client_account_1})

    url = txn.return_value[0]
    password = txn.return_value[1]

    assert url == expected_url
    assert password == expected_password


def test_factory_only_functions():

    torpedo_factory = deploy_TorpedoFactory()
    torpedo_session_address = deploy_session(torpedo_factory)
    torpedo_session = TorpedoSession.at(torpedo_session_address)

    client_account_1 = get_account(index=1)
    phaestus_acccount_1 = get_account(index=2)

    # currently set to be allowed
    # with pytest.raises(exceptions.VirtualMachineError):
    #     torpedo_session.getClientAddress.call({"from": client_account_1})

    client_address = torpedo_session.getClientAddress.call(
        {"from": torpedo_factory.address}
    )

    assert client_address == client_account_1

    phaestus_address = torpedo_session.getPhaestusAddress.call(
        {"from": torpedo_factory.address}
    )

    assert phaestus_address == phaestus_acccount_1


def test_get_session_request():

    torpedo_factory = deploy_TorpedoFactory()
    torpedo_session_address = deploy_session(torpedo_factory)
    torpedo_session = TorpedoSession.at(torpedo_session_address)

    client_account_1 = get_account(index=1)
    phaestus_account_1 = get_account(index=2)

    (
        numCPUs,
        numGPUs,
        totalTime,
        sessionGPUType,
        sessionServiceType,
        diskSpace,
        RAM,
    ) = torpedo_session.getSessionRequest()

    assert [
        numCPUs,
        numGPUs,
        totalTime,
        sessionGPUType,
        sessionServiceType,
        diskSpace,
        RAM,
    ] == [0, 1, 2, 1, 0, 4, 2]
