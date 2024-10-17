// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract VotingSystem is Ownable {
    struct Candidate {
        uint256 id;
        string name;
        uint256 voteCount;
        string imageURL;
    }

    struct Election {
        uint256 id;
        string name;
        uint256 candidateCount;
        uint256 voterCount;
        uint256 whitelistStartTime;
        uint256 whitelistEndTime;
        uint256 votingStartTime;
        uint256 votingEndTime;
        bool active;
        uint256 balance;
    }

    // Mappings
    mapping(uint256 => Election) public elections; // Mapping for elections
    mapping(uint256 => mapping(address => bool)) public isWhitelisted; // Whitelist for each election
    mapping(uint256 => mapping(address => bool)) public hasVoted; // Vote status for each election
    mapping(uint256 => mapping(uint256 => Candidate)) public candidates; // Candidates for each election
    mapping(uint256 => mapping(uint256 => address)) public registrationToWallet; // Map registration numbers to wallet addresses per election
    mapping(address => bool) public isElectionCreator; // Mapping to track who can create elections

    // Election counter
    uint256 public electionCount;
    uint256 public serviceFeePercentage;

    // Events
    event Whitelisted(uint256 electionId, address voter);
    event VoteCasted(uint256 electionId, address voter, uint256 candidateId);
    event CandidateAdded(
        uint256 electionId,
        uint256 candidateId,
        string name,
        string imageURL
    );
    event ElectionCreated(uint256 electionId, string name);
    event ElectionCreatorAdded(address creator);
    event ElectionCreatorRemoved(address creator);
    event DepositMade(uint256 electionId, uint amount, uint256 serviceFee);

    constructor() Ownable(msg.sender) {}

    // Modifiers for election-specific actions
    modifier onlyDuringWhitelist(uint256 _electionId) {
        require(
            block.timestamp >= elections[_electionId].whitelistStartTime &&
                block.timestamp <= elections[_electionId].whitelistEndTime,
            "Whitelist period is closed"
        );
        _;
    }

    modifier onlyDuringVoting(uint256 _electionId) {
        require(
            block.timestamp >= elections[_electionId].votingStartTime &&
                block.timestamp <= elections[_electionId].votingEndTime,
            "Voting period is closed"
        );
        _;
    }

    modifier onlyWhitelisted(uint256 _electionId) {
        require(
            isWhitelisted[_electionId][msg.sender],
            "You are not whitelisted to vote"
        );
        _;
    }

    // Modifier to allow only approved election creators
    modifier onlyElectionCreator() {
        require(
            isElectionCreator[msg.sender],
            "You are not authorized to create elections"
        );
        _;
    }

    function deposit(uint256 _electionID) external payable onlyElectionCreator {
        require(msg.value > 0, "Deposit amount must be greater than 0");
        // Calculate the service fee and add it to the balance of the election creator's wallet address
        uint256 serviceFee = (msg.value * serviceFeePercentage) / 100;
        elections[_electionID].balance += (msg.value - serviceFee);
        emit DepositMade(_electionID, msg.value, serviceFee);
    }

    // Function to add addresses to the election creator whitelist (only the owner can do this)
    function addElectionCreator(address _creator) external {
        require(
            !isElectionCreator[_creator],
            "The address is already a creator"
        );
        isElectionCreator[_creator] = true;
        emit ElectionCreatorAdded(_creator);
    }

    // Function to remove addresses from the election creator whitelist (only the owner can do this)
    function removeElectionCreator(address _creator) external {
        require(
            isElectionCreator[_creator],
            "The creator address does not exist"
        );
        isElectionCreator[_creator] = false;
        emit ElectionCreatorRemoved(_creator);
    }

    // Function to create a new election (only whitelisted election creators can call this)
    function createElection(
        string memory _name,
        uint256 _whitelistStartTime,
        uint256 _whitelistEndTime,
        uint256 _votingStartTime,
        uint256 _votingEndTime
    ) external onlyElectionCreator {
        require(
            _whitelistStartTime < _whitelistEndTime,
            "Whitelist end time must be after start time"
        );
        require(
            _votingStartTime < _votingEndTime,
            "Voting end time must be after start time"
        );

        electionCount++;
        elections[electionCount] = Election({
            id: electionCount,
            name: _name,
            candidateCount: 0,
            voterCount: 0,
            whitelistStartTime: _whitelistStartTime,
            whitelistEndTime: _whitelistEndTime,
            votingStartTime: _votingStartTime,
            votingEndTime: _votingEndTime,
            active: true,
            balance: 0
        });

        emit ElectionCreated(electionCount, _name);
    }

    // Whitelist function with registration number for an election
    function whitelistUser(
        uint256 _electionId,
        uint256 _registrationNumber
    ) external onlyDuringWhitelist(_electionId) {
        require(
            !isWhitelisted[_electionId][msg.sender],
            "User is already whitelisted"
        );
        require(
            registrationToWallet[_electionId][_registrationNumber] ==
                address(0),
            "This registration number is already linked to a wallet"
        );

        // Link registration number and whitelist the user for the specific election
        registrationToWallet[_electionId][_registrationNumber] = msg.sender;
        isWhitelisted[_electionId][msg.sender] = true;
        elections[_electionId].voterCount++;

        emit Whitelisted(_electionId, msg.sender);
    }

    // Voting function for a specific election
    function vote(
        uint256 _electionId,
        uint256 _candidateId
    ) external onlyWhitelisted(_electionId) onlyDuringVoting(_electionId) {
        require(!hasVoted[_electionId][msg.sender], "You have already voted");
        require(
            _candidateId > 0 &&
                _candidateId <= elections[_electionId].candidateCount,
            "Invalid candidate"
        );
        require(
            elections[_electionId].balance > 30000,
            "Insufficient gas in reserve to vote, tell the election creator"
        );
        // Mark the voter as having voted and increment the vote count of the selected candidate
        hasVoted[_electionId][msg.sender] = true;
        candidates[_electionId][_candidateId].voteCount += 1;
        elections[_electionId].balance -= 30000;
        emit VoteCasted(_electionId, msg.sender, _candidateId);
    }

    // Admin function to add candidates to a specific election
    function addCandidate(
        uint256 _electionId,
        string memory _name,
        string memory _imageURL
    ) external onlyOwner {
        // Ensure the election exists
        require(
            elections[_electionId].id == _electionId &&
                elections[_electionId].active,
            "Election does not exist"
        );

        // Increment candidate count for the election
        elections[_electionId].candidateCount++;
        uint256 candidateId = elections[_electionId].candidateCount;

        // Add the candidate to the mapping
        candidates[_electionId][candidateId] = Candidate(
            candidateId,
            _name,
            0,
            _imageURL
        );

        emit CandidateAdded(_electionId, candidateId, _name, _imageURL);
    }

    // Function to get candidate information for a specific election
    function getCandidate(
        uint256 _electionId,
        uint256 _candidateId
    ) external view returns (Candidate memory) {
        return candidates[_electionId][_candidateId];
    }

    // Function to get all candidates for a specific election
    function getCandidates(
        uint256 _electionId
    ) external view returns (Candidate[] memory) {
        uint256 candidateCount = elections[_electionId].candidateCount;
        Candidate[] memory candidateArray = new Candidate[](candidateCount);
        for (uint256 i = 1; i <= candidateCount; i++) {
            candidateArray[i - 1] = candidates[_electionId][i];
        }
        return candidateArray;
    }

    // Function to check if a registration number is linked to a wallet in a specific election
    function getWalletForRegistration(
        uint256 _electionId,
        uint256 _registrationNumber
    ) public view returns (address) {
        return registrationToWallet[_electionId][_registrationNumber];
    }

    // Function to get the total number of registered voters in a specific election
    function getTotalRegisteredVoters(
        uint256 _electionId
    ) external view returns (uint256) {
        return elections[_electionId].voterCount;
    }

    function getGasReserve(
        uint256 _electionId
    ) external view returns (uint256) {
        return elections[_electionId].balance;
    }
}