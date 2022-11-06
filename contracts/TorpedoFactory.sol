// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./TorpedoSession.sol";

interface IMidpoint {
    function callMidpoint(uint64 midpointId, bytes calldata args)
        external
        returns (uint256 requestId);
}

contract TorpedoFactory {
    // ---------------------------- Constants ----------------------------

    // Save the owner address
    address public owner;
    uint256 rate_precision = 100;
    uint256 LARGE_NUMBER = 10000000000000;
    uint256[] minimals;
    uint256 priceEstimate;

    // Contract to get accurate pricing data
    AggregatorV3Interface public priceFeed;

    // ---------------------------- Structs/Enums--------------------------------

    // GPU types
    enum gpuType {
        NONE,
        _3090,
        A100,
        K80
    }

    // Service Types
    enum serviceType {
        GCP,
        AWS,
        VAST,
        AZURE
    }

    struct PhaestusStatus {
        bool status;
        address sessionAddress;
    }

    // Phaestus Object
    struct Phaestus {
        address payable phaestusAddress;
        uint8 numCPUs;
        uint8 numGPUs;
        uint256 endTime; // in hours
        uint256 rate; // USD per hour rate of the node
        gpuType gpuType;
        serviceType serviceType;
        uint256 diskSpace; // Persistent storage on disk (GB)
        uint256 RAM; //RAM available to offer (GB)
    }

    // Session Request Object:
    // TODO: Add an array of offered services. GCP/AWS/Vast Enum service type
    struct SessionRequest {
        uint8 numCPUs;
        uint8 numGPUs;
        uint16 totalTime; // in hours
        gpuType gpuType;
        serviceType serviceType;
        uint256 diskSpace;
        uint256 RAM;
    }

    // ---------------------------- Mappings ---------------------------------

    // Mappings for user addresses to Clients or Phaestus nodes.
    mapping(address => address) clientToSession;
    mapping(address => Phaestus) public addressToPhaestus;
    mapping(address => PhaestusStatus) public phaestusToActivate;

    // ---------------------------- Storage Arrays ---------------------------------

    //Storing Phaestus Nodes in arrays
    Phaestus[] public phaestusNodes;

    // ---------------------------- Modifiers ---------------------------------

    modifier onlyOwner() {
        require(msg.sender == owner, "You are not the Owner");
        _;
    }

    // ---------------------------- Constructor ---------------------------------

    constructor(address _priceFeed) public {
        priceFeed = AggregatorV3Interface(_priceFeed);
        owner = msg.sender;
    }

    // ----------------------------  Public View Functions ---------------------------------

    // View phaestus nodes
    // TODO: return entire array of phaestus nodes
    function viewPhaestus(uint256 index) public view returns (Phaestus memory) {
        return phaestusNodes[index];
    }

    // Return entire array of Phaestus nodes
    function viewAllPhaestus() public view returns (Phaestus[] memory) {
        return phaestusNodes;
    }

    // This needs to be locked. Or like please change this bc race conditions and all sorts of mayhem
    function toggle(address phaestusNode) public {
        phaestusToActivate[phaestusNode].sessionAddress = msg.sender;
        phaestusToActivate[phaestusNode].status = !phaestusToActivate[
            phaestusNode
        ].status;
    }

    // Returns 1 if there is an outstanding session for that phaestus node
    function checkStatusOfPhaestus() public view returns (bool) {
        return phaestusToActivate[msg.sender].status;
    }

    // Returns the session address for the querying phaestus node
    function getSessionAddress() public view returns (address) {
        return phaestusToActivate[msg.sender].sessionAddress;
    }

    // Returns cost in USD
    function calculateUSDCost(SessionRequest memory sessionRequest)
        public
        view
        returns (uint256)
    {
        // Finds the cheapest phaestus node with the required services
        uint256 index = findBestPhaestus(sessionRequest);

        // retrieve rate and use it to calculate total amount
        uint256 cost = phaestusNodes[uint256(index)].rate *
            sessionRequest.totalTime;

        return cost;
    }

    //returns the rate precision
    function getRatePrecision() public view returns (uint256) {
        return rate_precision;
    }

    // Return cost in Wei (times the precision)
    function calculateWeiCost(SessionRequest memory sessionRequest)
        public
        view
        returns (uint256)
    {
        uint256 cost = USDToWei(calculateUSDCost(sessionRequest)) /
            rate_precision;
        return cost;
    }

    // Converts Eth to USD
    function EthToUSD(uint256 ethAmount) public view returns (uint256) {
        uint256 ethPrice = getPrice();
        uint256 ethAmountInUsd = (ethPrice * ethAmount) / 1000000000000000000;
        return ethAmountInUsd;
    }

    // Converts USD to Wei
    function USDToWei(uint256 USD) public view returns (uint256) {
        // minimumUSD
        uint256 minimumUSD = USD * 10**18;
        uint256 price = getPrice();
        uint256 precision = 1 * 10**18;
        // return (minimumUSD * precision) / price;
        // We fixed a rounding error by adding one!
        return ((minimumUSD * precision) / price) + 1;
    }

    // Get current time
    function getNow() public view returns (uint256) {
        return block.timestamp;
    }

    function getPoolTVL()
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        // Arbitrary large number (fix later)
        uint256 sumCPUs = 0;
        uint256 sumGPUs = 0;
        // uint256 maxRAM = 0;
        uint256 sumTime = 0;
        uint256 sumDiskSpace;
        uint256 sumRAM;
        uint256 i;

        //Loop over all available phaestus nodes:
        for (i = 0; i < phaestusNodes.length; i++) {
            Phaestus memory p = phaestusNodes[i];

            sumCPUs += p.numCPUs;

            sumGPUs += p.numGPUs;

            sumTime += p.endTime - block.timestamp;

            sumDiskSpace += p.diskSpace;

            sumRAM += p.RAM;
        }

        sumTime = uint256(sumTime / 3600);

        // change max time to hours

        return (sumCPUs, sumGPUs, sumTime, sumDiskSpace, sumRAM);
    }

    // ----------------------------  Internal functions ---------------------------------

    // finding cheapest phaestus node that satisfies session params
    function findBestPhaestus(SessionRequest memory sessionRequest)
        internal
        view
        returns (uint256)
    {
        // Arbitrary large number (fix later)
        uint256 min_index = LARGE_NUMBER;
        uint256 min_rate = LARGE_NUMBER;
        uint256 i;

        // Change the rate variable to a function that takes in a session request and calculates
        for (i = 0; i < phaestusNodes.length; i++) {
            Phaestus memory p = phaestusNodes[i];

            if (
                p.numCPUs >= sessionRequest.numCPUs &&
                p.numGPUs >= sessionRequest.numGPUs &&
                p.diskSpace >= sessionRequest.diskSpace &&
                p.RAM >= sessionRequest.RAM &&
                p.gpuType == sessionRequest.gpuType &&
                p.serviceType == sessionRequest.serviceType &&
                min_rate > p.rate
            ) {
                min_rate = p.rate;
                min_index = i;
            }
        }
        return min_index;
    }

    // Get price of ETH
    function getPrice() internal view returns (uint256) {
        (, int256 answer, , , ) = priceFeed.latestRoundData();
        return uint256(answer * 10000000000);
    }

    //Get GCP Price for given params
    function getGCPPrice(
        uint256 timeInSeconds,
        uint256 numCPUs,
        uint256 RAM
    ) public returns (uint256) {
        address startpointAddress = 0x9BEa2A4C2d84334287D60D6c36Ab45CB453821eB;
        uint64 midpointID = 445;
        bytes memory args = abi.encodePacked(timeInSeconds, numCPUs, RAM);
        uint256 requestId = IMidpoint(startpointAddress).callMidpoint(
            midpointID,
            args
        );

        return priceEstimate;
    }

    //Callback function
    function callbackMidpoint(
        uint256 requestId,
        uint64 _midpointId,
        uint256 _priceEstimate
    ) public returns (uint256) {
        priceEstimate = _priceEstimate;
    }

    // Finds all nodes with lowest rate that satisfy the session params
    function findAllBestPhaestus(SessionRequest memory sessionRequest)
        internal
        returns (uint256[] storage)
    {
        uint256 i = findBestPhaestus(sessionRequest);
        Phaestus memory best = phaestusNodes[i];

        for (uint256 j = 0; j < phaestusNodes.length; j++) {
            Phaestus memory p = phaestusNodes[j];

            if (p.rate == best.rate) {
                minimals.push(j);
            }
        }
        return minimals;
    }

    // ----------------------------  External functions ---------------------------------

    // Register a Phaestus Node
    // Make payable later, and require collateral...build reputation
    // PHAESTUS NODE CALLS THIS FUNCTION TO REGISTER ITSELF
    function registerPhaestus(
        uint8 numCPUs,
        uint8 numGPUs,
        uint256 endTime,
        uint256 rate,
        gpuType _gpuType,
        serviceType _serviceType,
        uint256 diskSpace,
        uint256 RAM
    ) external {
        // Phaestus node has at least 2 CPUS, non-zero GPUs and is online for 4 hours
        require(numCPUs >= 1, "Must have at least 2 CPU cores");
        require(numGPUs >= 0, "GPUs must be non-negative");
        require(
            endTime > block.timestamp + 2 * 3600,
            "Phaestus must be online for at least 2 hours"
        );
        if (numGPUs > 0) {
            require(
                _gpuType != gpuType.NONE,
                "You have a GPU. Specify type please"
            );
        }

        // Add node to the list of nodes
        phaestusNodes.push(
            Phaestus({
                phaestusAddress: payable(msg.sender),
                numCPUs: numCPUs,
                numGPUs: numGPUs,
                endTime: endTime,
                rate: rate,
                gpuType: _gpuType,
                serviceType: _serviceType,
                diskSpace: diskSpace,
                RAM: RAM
            })
        );

        addressToPhaestus[msg.sender] = phaestusNodes[phaestusNodes.length - 1];
        phaestusToActivate[msg.sender].status = false;
    }

    // function updatePhaestusSpecs() {

    //     }

    // How to protect these functions! Check this
    function deductResources() external {
        TorpedoSession session = TorpedoSession(msg.sender);

        // phaestus can use past session creds to change resource values...FIX ME

        Phaestus storage p = addressToPhaestus[session.getPhaestusAddress()];

        p.numCPUs -= session.numCPUs();
        p.numGPUs -= session.numGPUs();
        p.RAM -= session.RAM();
        p.diskSpace -= session.diskSpace();

        // addressToPhaestus[msg.sender] = p;
        // addressToPhaestus[msg.sender].numCPUs -= _numCPUs;
        // addressToPhaestus[msg.sender].numGPUs -= _numGPUs;
    }

    function releaseResources() external {
        TorpedoSession session = TorpedoSession(msg.sender);

        Phaestus storage p = addressToPhaestus[session.getPhaestusAddress()];

        p.numCPUs += session.numCPUs();
        p.numGPUs += session.numGPUs();
        p.RAM += session.RAM();
        p.diskSpace += session.diskSpace();
        // addressToPhaestus[msg.sender].numCPUs += _numCPUs;
        // addressToPhaestus[msg.sender].numGPUs += _numGPUs;
    }

    // ----------------------------  Payable functions ---------------------------------

    // CLIENT WILL USE THIS FUNCTION TO INSTANTIATE A SESSION
    function createSession(SessionRequest memory sessionRequest)
        public
        payable
        returns (address)
    {
        // check payment is at least what is required
        require(
            msg.value >= calculateWeiCost(sessionRequest),
            "insufficient payment"
        );

        // Find all phaestus nodes that offer that rate
        minimals = findAllBestPhaestus(sessionRequest);

        // @dev Eventually switch to oracle source of randomness
        //select a phaestus node at random from the above valid nodes
        uint256 phaestus_chosen = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.difficulty))
        ) % minimals.length;
        address payable phaestus_address = phaestusNodes[phaestus_chosen]
            .phaestusAddress;

        // Initiate session contract with client and phaestus
        TorpedoSession _clientSession = (new TorpedoSession){value: msg.value}(
            sessionRequest.numCPUs,
            sessionRequest.numGPUs,
            sessionRequest.totalTime,
            sessionRequest.gpuType,
            sessionRequest.diskSpace,
            sessionRequest.RAM,
            sessionRequest.serviceType,
            payable(msg.sender),
            phaestus_address
        );

        // map client address to session contract address
        clientToSession[msg.sender] = address(_clientSession);

        // Reset minimals array
        minimals = new uint256[](0);

        // Return session contract address
        return address(_clientSession);
    }

    // CLIENT CALLS THIS TO EXTEND SESSION
    function extendSession(uint256 addedTime) public payable {
        address _sessionAddress = clientToSession[msg.sender];
        // require(_sessionAddress != 0, "You are an invalid client");
        TorpedoSession session = TorpedoSession(_sessionAddress);
        address payable _phaestus = session.getPhaestusAddress();

        require(
            msg.sender == session.getClientAddress(),
            "Sender is not client of the session"
        );
        require(
            block.timestamp + addedTime < addressToPhaestus[_phaestus].endTime,
            "This phaestus won't be online for that long"
        );

        uint256 addedCost = USDToWei(
            addressToPhaestus[_phaestus].rate * addedTime
        ) / rate_precision;

        require(msg.value > addedCost, "Insufficient payment");

        session.extendSession{value: msg.value}(addedTime);
    }

    function getClientSessionAddress() public view returns (address) {
        return clientToSession[msg.sender];
    }
}
