from brownie import (
    accounts,
    TorpedoFactory,
    network,
    config,
    MockV3Aggregator,
    TorpedoSession,
)
from scripts.helpers import get_account, deploy_mocks, LOCAL_BLOCKCHAIN_ENVIRONMENTS
from time import time, sleep

ETH_AMOUNT = 1
WEI_TO_ETH = 1000000000000000000


def deploy_TorpedoFactory():
    account = get_account()
    phaestus_account_1 = get_account()
    # publish_source=True
    if network.show_active() not in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        price_feed_address = config["networks"][network.show_active()][
            "eth_usd_price_feed"
        ]
    else:
        deploy_mocks()
        price_feed_address = MockV3Aggregator[-1].address

    torpedo_factory = TorpedoFactory.deploy(
        price_feed_address,
        {"from": account},
        publish_source=config["networks"][network.show_active()].get("verify"),
    )
    sleep(2)
    # deploy a dummy phaestus node into torpedo
    # now = torpedo_factory.getNow()
    # sleep(2)
    # torpedo_factory.registerPhaestus(
    #     4, 2, now + 4 * 3600 * 8, 1, 1, 0, 20, 12, {"from": phaestus_account_1}
    # )
    # sleep(2)
    # torpedo_factory.registerPhaestus(
    #     8, 1, now + 12 * 3600 * 8, 1, 1, 0, 50, 24, {"from": phaestus_account_1}
    # )
    # sleep(2)
    return torpedo_factory


def deploy_session(torpedo_factory):
    client_account_1 = get_account(index=1)
    phaestus_account_1 = get_account(index=2)

    now = torpedo_factory.getNow()
    torpedo_factory.registerPhaestus(
        3, 3, now + 4 * 3600 * 8, 1, 1, 0, 20, 12, {"from": phaestus_account_1}
    )

    address = torpedo_factory.createSession(
        [0, 1, 2, 1, 0, 4, 2],
        {"from": client_account_1, "value": 2 * WEI_TO_ETH},
    )

    return address.return_value


def do_stuff(torpedo_factory, torpedo_session_address):

    client_account_1 = get_account(index=1)
    phaestus_account_1 = get_account(index=2)

    torpedo_session = TorpedoSession.at(torpedo_session_address)

    torpedo_session.initialiseSession(
        "https://torpedo.one/phaestus-node-42/", "boogie", {"from": phaestus_account_1}
    )

    txn = torpedo_session.startSession({"from": client_account_1})

    url = txn.return_value[0]
    password = txn.return_value[1]

    print(url)
    print(password)


def add_phaestus():
    torpedo_factory = TorpedoFactory[-1]

    now = torpedo_factory.getNow()

    account = get_account()

    torpedo_factory.registerPhaestus(
        3, 3, now + 4 * 3600 * 8, 1, 1, 0, 20, 12, {"from": account}
    )

    print("Phaestus deployed")


def main():
    tf = deploy_TorpedoFactory()

    print("Contract deployed at: " + str(tf.address))

    # sesh = deploy_session(gf)
    # do_stuff(gf, sesh)

    # add_phaestus()
    # print("No function running here")
