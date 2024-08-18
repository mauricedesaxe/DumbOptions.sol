// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "../../lib/chainlink/AggregatorV3Interface.sol";

contract MockOracleFeed is AggregatorV3Interface {
    uint8 public decimals;
    string public description;
    uint256 public version = 3;

    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    RoundData[] public rounds;

    constructor(uint8 _decimals, string memory _description) {
        decimals = _decimals;
        description = _description;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        virtual
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory round = rounds[_roundId];
        return (round.roundId, round.answer, round.startedAt, round.updatedAt, round.answeredInRound);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory round = rounds[rounds.length - 1];
        return (round.roundId, round.answer, round.startedAt, round.updatedAt, round.answeredInRound);
    }

    function addRound(int256 _answer) external {
        uint80 nonce = uint80(rounds.length);
        rounds.push(RoundData(nonce, _answer, block.timestamp, block.timestamp, nonce));
    }

    function addRoundWithTimestamp(int256 _answer, uint256 _timestamp) external {
        uint80 nonce = uint80(rounds.length);
        rounds.push(RoundData(nonce, _answer, block.timestamp, _timestamp, nonce));
    }
}
