// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;


import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";


/// @title Lottery contract
/// @author I.Lieskov
/// @notice Contract use Chainlink Oracle for generating random words and get data about ETH/USD price
/// @dev Needs to fund subscription and add contract address as a consumer on https://vrf.chain.link/rinkeby in order to work with VRFv2
/// @custom:experimental This is an experimental contract.
contract Lottery is VRFConsumerBaseV2 {

                                                  // Rinkeby contract address
  AggregatorV3Interface internal immutable ethUsdPriceFeed; //= AggregatorV3Interface(0x8A753747A1Fa494EC906cE90E9f37563A8AF630e); // Rinkeby ETH/USD Data Feed
  VRFCoordinatorV2Interface COORDINATOR;

  enum LOTTERY_STATE{OPEN, CLOSED, CALCULATING_WINNER}
  LOTTERY_STATE public lotteryState;
  // Your subscription ID.
  uint64 s_subscriptionId;
  uint public usdParticipationFee = 50;
  address payable[] public players;
  uint public lotteryId = 0;

  mapping(address payable=> uint) userTickets;
  mapping(uint => address payable) public lotteryWinners; 

  event RequestedRandomness(uint requestId);

                          // Rinkeby coordinator address
  address immutable vrfCoordinator; //= 0x6168499c0cFfCaCD319c818142124B7A15E857ab;

  // The gas lane to use, which specifies the maximum gas price to bump to.
                   // Rinkeby KeyHash
  bytes32 immutable keyHash; // = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;


  // 150000 is a safe size for contract on Rinkeby network to work properly
  uint32 constant callbackGasLimit = 150000;

  uint16 constant requestConfirmations = 3;

 
  uint32 constant numWords = 1;

  uint256[] public s_randomWords;
  uint256 public s_requestId;
  address payable s_owner;


// Needs to fund subscription and add contract address as a consumer on 
// https://vrf.chain.link/rinkeby in order to work with VRFv2

  constructor(uint64 subscriptionId, 
              AggregatorV3Interface _ethUsdPriceFeed, 
              address _vrfCoordinator,
              bytes32 _keyHash) 
  VRFConsumerBaseV2(_vrfCoordinator) {
    COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
    s_owner = payable(msg.sender);
    s_subscriptionId = subscriptionId;
    ethUsdPriceFeed = _ethUsdPriceFeed;
    vrfCoordinator = _vrfCoordinator;
    keyHash = _keyHash;
    
    lotteryState = LOTTERY_STATE.CLOSED;
  }


    /// @notice Save and reset previous lottery data and start a new lottery
    /// @dev The Alexandr N. Tetearing algorithm could increase precision
    function startLottery() public onlyOwner{
      require(lotteryState == LOTTERY_STATE.CLOSED, "Can't start a new lottery");
      players = new address payable[](0);
      lotteryState = LOTTERY_STATE.OPEN;
      lotteryId++;
      s_randomWords = new uint[](0);
    }

  function participate() public payable{
      require(msg.value >= getParticipationFee(), "Not Enough ETH to participate!");
      require(lotteryState == LOTTERY_STATE.OPEN, "The lottery is closed. Wait until the next lottery");
      players.push(payable(msg.sender));
    }

  function getParticipationFee() public view returns(uint){
        uint precision = 1 * 10 ** 18;
        uint price = uint(getLatestPrice());
        uint costToParticipate = (precision / price) * (usdParticipationFee * 100000000);
        return costToParticipate;
    }

  function getLatestPrice() public view returns(int){
      (
        /*uint80 roundID*/,
        int price,
        /*uint startedAt*/,
        /*uint timeStamp*/,
        /*uint80 answeredInRound*/
        ) = ethUsdPriceFeed.latestRoundData();

        return price;
    }

  function endLottery() public onlyOwner{
        require(lotteryState == LOTTERY_STATE.OPEN, "Can't end lottery yet");
        require(players.length > 0, "Can't divide by zero participants");
        lotteryState = LOTTERY_STATE.CALCULATING_WINNER;
        pickWinner();
        }
  
  // Assumes the subscription is funded sufficiently.
  function pickWinner() public onlyOwner{
        require(lotteryState == LOTTERY_STATE.CALCULATING_WINNER, "Needs to be calculating the winner");
        // Will revert if subscription is not set and funded.
        s_requestId = COORDINATOR.requestRandomWords(
              keyHash,
              s_subscriptionId,
              requestConfirmations,
              callbackGasLimit,
              numWords
             );
        emit RequestedRandomness(s_requestId);
        }


  function fulfillRandomWords(
    uint256, /* requestId */
    uint256[] memory random
  ) internal override {
    s_randomWords = random;
    require(s_randomWords[0] > 0, "random number not found");
    uint index = s_randomWords[0] % players.length;
    lotteryState = LOTTERY_STATE.CLOSED;
    lotteryWinners[lotteryId] = players[index]; 
    players[index].transfer(address(this).balance * 90 / 100);
    s_owner.transfer(address(this).balance);
  }


  modifier onlyOwner() {
    require(msg.sender == s_owner);
    _;
  }

  function getLotteryBalance() public view returns (uint) {
    return address(this).balance;
    }
}
