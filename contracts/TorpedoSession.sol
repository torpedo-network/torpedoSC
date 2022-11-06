// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./TorpedoFactory.sol";

contract TorpedoSession is Ownable {
    // ---------------------------- Constants ---------------------------------
    uint8 public numCPUs;
    uint8 public numGPUs;

    uint256 public diskSpace;
    uint256 public RAM;

    uint256 startTime;
    uint256 endTime;
    uint256 totalTime;
    uint256 precision = 3;

    address payable clientAddress;
    address payable phaestusAddress;

    string _url;
    mapping(bytes32 => string) password; // key : Hash(client,phaestus)

    uint256 sessionBalance;

    TorpedoFactory.gpuType sessionGPUType;
    TorpedoFactory.serviceType sessionServiceType;

    TorpedoFactory factory;

    // ---------------------------- Enums ---------------------------------
    enum Status {
        INITIALISING,
        PHAESTUS_CONFIGURED,
        ENGAGED,
        ENDED,
        RESOLVED
    }

    Status public status;

    // ---------------------------- Modifiers ---------------------------------

    modifier onlyPhaestus() {
        require(msg.sender == phaestusAddress, "You are not sessions Phaestus");
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == address(factory), "You are not the factory");
        _;
    }

    // ---------------------------- Constructor ---------------------------------

    constructor(
        uint8 _numCPUs,
        uint8 _numGPUs,
        uint256 _totalTime,
        TorpedoFactory.gpuType _gpuType,
        uint256 _diskSpace,
        uint256 _RAM,
        TorpedoFactory.serviceType _serviceType,
        address payable _clientAddress,
        address payable _phaestusAddress
    ) public payable {
        // Set resource usage params
        numCPUs = _numCPUs;
        numGPUs = _numGPUs;
        diskSpace = _diskSpace;
        RAM = _RAM;

        sessionGPUType = _gpuType;
        sessionServiceType = _serviceType;

        totalTime = _totalTime;

        // Set contract addresses
        clientAddress = _clientAddress;
        phaestusAddress = _phaestusAddress;

        // Transfer ownership of the contract to the client
        // SHOULD THIS BE PHAESTUS ?
        transferOwnership(clientAddress);

        factory = TorpedoFactory(msg.sender);
        sessionBalance = msg.value;

        // Set the phaestus flag to active
        factory.toggle(phaestusAddress);

        status = Status.INITIALISING;
    }

    // ---------------------------- Pure Functions ---------------------------------

    // Using idea from  https://docs.avax.network/community/tutorials-contest/avax-chat-dapp/
    // To set up secure passing of ssh key.
    // Returns a unique code for the channel created between the two users
    // Hash(key1,key2) where key1 is lexicographically smaller than key2
    function _getHash(address pubkey1, address pubkey2)
        internal
        pure
        returns (bytes32)
    {
        if (pubkey1 < pubkey2)
            return keccak256(abi.encodePacked(pubkey1, pubkey2));
        else return keccak256(abi.encodePacked(pubkey2, pubkey1));
    }

    // ---------------------------- Password Getter/Setter Functions ---------------------------------

    // Phaestus node sets password
    function setPassword(string memory _password) internal onlyPhaestus {
        require(status == Status.INITIALISING, "Session is not initialising");
        bytes32 _hash = _getHash(msg.sender, clientAddress);
        password[_hash] = _password;
    }

    // Client accesses password
    function getPassword() internal onlyOwner returns (string memory) {
        require(
            status >= Status.PHAESTUS_CONFIGURED,
            "Session is past configuration"
        );
        require(status < Status.RESOLVED, "Session is resolved");

        // Access password
        bytes32 _hash = _getHash(msg.sender, phaestusAddress);
        string memory _password = password[_hash];

        return _password;
    }

    function setUrl(string memory _notebook_url) internal onlyPhaestus {
        _url = _notebook_url;
    }

    function getUrl() internal onlyOwner returns (string memory) {
        return _url;
    }

    // ---------------------------- Client functions ---------------------------------

    // CLIENT CALLS THIS TO RECIEVE CREDENTIALS
    function startSession()
        public
        onlyOwner
        returns (string memory, string memory)
    {
        require(
            status >= Status.PHAESTUS_CONFIGURED,
            "Session is not configured"
        );
        string memory session_url = getUrl();
        string memory session_password = getPassword();

        status = Status.ENGAGED;

        return (session_url, session_password);
    }

    // ---------------------------- Phaestus functions ---------------------------------

    //Phaestus calls this function to get the session information:
    function getSessionRequest()
        public
        view
        returns (
            uint8,
            uint8,
            uint256, // in hours
            TorpedoFactory.gpuType,
            TorpedoFactory.serviceType,
            uint256,
            uint256
        )
    {
        return (
            numCPUs,
            numGPUs,
            totalTime,
            sessionGPUType,
            sessionServiceType,
            diskSpace,
            RAM
        );
    }

    // PHAESTUS CALLS THIS FUNCTION TO SET UP SESSION
    function initialiseSession(
        string memory _notebook_url,
        string memory _password
    ) public onlyPhaestus {
        // Edit resource count on phaestus
        factory.deductResources();

        // Set url and password
        setUrl(_notebook_url);
        setPassword(_password);

        // Set session end time
        startTime = block.timestamp;
        endTime = block.timestamp + totalTime;

        // Phaestus configured status.
        status = Status.PHAESTUS_CONFIGURED;

        // add toggle
        factory.toggle(msg.sender);
    }

    // ---------------------------- Internal functions ---------------------------------
    // TODO: send phaestus all system stats
    // calculates how much of the sesssion is over
    function _calculateSessionUsage() internal view returns (uint256) {
        uint256 numerator = (block.timestamp - startTime) * 10**(precision + 1);
        uint256 quotient = ((numerator / totalTime) + 5) / 10;

        return quotient;
    }

    // End session routine
    function _endSession() internal {
        require(status == Status.ENDED, "Session has not ended yet");

        // Calculate amount of eth used
        uint256 sessionUsage = _calculateSessionUsage();

        // Check if session went overtime
        if (sessionUsage > 1 * precision) {
            phaestusAddress.transfer(sessionBalance);
        } else {
            uint256 amountUsed = (sessionUsage * sessionBalance) / precision;

            // give respective eth back to client and phaestus
            phaestusAddress.transfer(amountUsed);

            clientAddress.transfer(address(this).balance);
        }

        factory.releaseResources();

        status = Status.RESOLVED;
    }

    // ---------------------------- End Session functions  ---------------------------------

    // CALLED BY CLIENT
    function endSession() public onlyOwner {
        status = Status.ENDED;
        _endSession();
    }

    // CALLED BY PHAESTUS
    function sessionOvertime() public onlyPhaestus {
        require(block.timestamp > endTime, "Session is not overtime");
        status = Status.ENDED;
        _endSession();
    }

    function extendSession(uint256 addedTime) public payable onlyFactory {
        endTime += addedTime;
        totalTime += addedTime;
    }

    // ---------------------------- Only Factory functions  ---------------------------------
    function getPhaestusAddress()
        public
        view
        onlyFactory
        returns (address payable)
    {
        return phaestusAddress;
    }

    function getClientAddress() public view returns (address payable) {
        return clientAddress;
    }
}
