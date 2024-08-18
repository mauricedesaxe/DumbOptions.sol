// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "../lib/chainlink/AggregatorV3Interface.sol";

/**
 * @title Option
 * @author MauriceDeSaxe
 * @notice When you deploy this contract you effectively create an option that you sell.
 * You set the strike price, the expiration date and the Chainlink feed you want to use for pricing.
 * A buyer can later buy the option from you under the terms provided, if the option hasn't expired yet.
 * If at any point the strike price is reached, anyone can call `tryFinalize()` to
 * determine and set the "winner" of the option. If the option expires, the seller
 * wins. The seller can cancel the option at any time, if someone didn't buy it yet.
 */
contract Option {
    // <errors>
    // common errors
    error ErrorFeedNotLive();
    error ErrorOptionCanceled();
    error ErrorOptionNotFinalized();
    error ErrorOptionAlreadySold();

    // constructor errors
    error ErrorFeedAddressZero();
    error ErrorHeartbeatZero();
    error ErrorStrikePriceEqualLatestPrice();
    error ErrorExpirationBeforeExpirationDelay();

    // buy errors
    error ErrorOptionExpired();
    error ErrorAmountNotEqual();

    // tryFinalize errors
    error ErrorNoWinnerFound();
    error ErrorOptionAlreadyFinalized();

    // withdraw errors
    error ErrorOnlyWinnerCanWithdraw();
    error ErrorInsufficientBalance();
    error ErrorWithdrawFailed();

    // cancel errors
    error ErrorOnlySellerCanCancel();
    error ErrorOptionAlreadyCanceled();
    // </errors>

    // <types>
    enum OptionType {
        CALL,
        PUT
    }

    struct FeedParameters {
        address feed;
        uint256 heartbeat;
    }

    struct OptionParameters {
        OptionType optionType;
        int256 startingPrice;
        int256 strikePrice;
        uint256 expiration;
    }

    struct DealParameters {
        address buyer;
        address seller;
        uint256 amount;
        address winner;
    }
    // </types>

    // <events>
    event OptionCreated(
        address indexed feed,
        OptionType indexed optionType,
        uint256 amount,
        int256 startingPrice,
        int256 strikePrice,
        uint256 expiration
    );
    event OptionBought(address indexed buyer, uint256 amount);
    event OptionCanceled(address indexed user, uint256 amount);
    event OptionFinalized(address indexed winner, uint256 amount);
    event OptionWithdrawn(address indexed user, uint256 amount);
    // </events>

    // <state>
    uint256 public constant EXPIRATION_DELAY = 1 minutes;

    FeedParameters public feedParameters;
    OptionParameters public optionParameters;
    DealParameters public dealParameters;
    bool public isCanceled;
    // </state>

    constructor(address _feed, uint256 _heartbeat, int256 _strikePrice, uint256 _expirationTimestamp) payable {
        if (_feed == address(0)) {
            revert ErrorFeedAddressZero();
        }

        if (_heartbeat == 0) {
            revert ErrorHeartbeatZero();
        }

        (int256 latestPrice, uint256 latestTimestamp) = _getCurrentPrice(_feed);

        if (!_isFeedLive(latestTimestamp, _heartbeat)) {
            revert ErrorFeedNotLive();
        }

        if (_strikePrice == latestPrice) {
            revert ErrorStrikePriceEqualLatestPrice();
        }

        if (_expirationTimestamp <= block.timestamp + EXPIRATION_DELAY) {
            revert ErrorExpirationBeforeExpirationDelay();
        }

        feedParameters.feed = _feed;
        feedParameters.heartbeat = _heartbeat;

        optionParameters.startingPrice = latestPrice;
        optionParameters.strikePrice = _strikePrice;
        optionParameters.expiration = _expirationTimestamp;

        if (_strikePrice > latestPrice) {
            optionParameters.optionType = OptionType.CALL;
        } else {
            optionParameters.optionType = OptionType.PUT;
        }

        dealParameters.seller = msg.sender;
        dealParameters.amount = msg.value;

        emit OptionCreated(
            feedParameters.feed,
            optionParameters.optionType,
            dealParameters.amount,
            optionParameters.startingPrice,
            optionParameters.strikePrice,
            optionParameters.expiration
        );
    }

    /**
     * @notice Returns the current price and timestamp from the feed.
     * @return answer The current price from the feed.
     * @return timestamp The timestamp of the current price.
     */
    function _getCurrentPrice(address _feedAddress) internal view returns (int256 answer, uint256 timestamp) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(_feedAddress);
        (
            /* uint80 roundID */
            ,
            answer,
            /*uint startedAt*/
            ,
            timestamp,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return (answer, timestamp);
    }

    /**
     * @notice Checks if the feed is live.
     * @param _latestTimestamp The timestamp of the latest price from the feed.
     * @param _heartbeat The heartbeat of the feed.
     * @return true if the feed is live, false otherwise.
     */
    function _isFeedLive(uint256 _latestTimestamp, uint256 _heartbeat) internal view returns (bool) {
        if (_latestTimestamp == 0) {
            return false;
        }

        if (_latestTimestamp > block.timestamp) {
            return false;
        }

        uint256 elapsed = block.timestamp - _latestTimestamp;
        return elapsed < _heartbeat;
    }

    /**
     * @notice Buy the option.
     */
    function buy() public payable {
        if (isCanceled) {
            revert ErrorOptionCanceled();
        }

        if (block.timestamp > optionParameters.expiration) {
            revert ErrorOptionExpired();
        }
        if (dealParameters.buyer != address(0)) {
            revert ErrorOptionAlreadySold();
        }
        if (msg.value != dealParameters.amount) {
            revert ErrorAmountNotEqual();
        }

        dealParameters.buyer = msg.sender;

        emit OptionBought(msg.sender, dealParameters.amount);
    }

    /**
     * @notice Checks if there is a winner and sets the winner, finalizing the option.
     */
    function tryFinalize() public {
        if (isCanceled) {
            revert ErrorOptionCanceled();
        }

        if (dealParameters.winner != address(0)) {
            revert ErrorOptionAlreadyFinalized();
        }

        if (_isExpired()) {
            // early return if the option is expired; the seller wins
            dealParameters.winner = dealParameters.seller;
            emit OptionFinalized(dealParameters.seller, dealParameters.amount);
            return;
        }

        // if not expired, check feed liveness and get price
        (int256 latestPrice, uint256 latestTimestamp) = _getCurrentPrice(feedParameters.feed);
        if (!_isFeedLive(latestTimestamp, feedParameters.heartbeat)) {
            revert ErrorFeedNotLive();
        }

        // if the price didn't hit the strike price, nobody wins yet
        if (!_isStrikePriceHit(latestPrice)) {
            revert ErrorNoWinnerFound();
        }

        // if the price hit the strike price, the buyer wins
        dealParameters.winner = dealParameters.buyer;
        emit OptionFinalized(dealParameters.winner, dealParameters.amount);
    }

    function _isExpired() internal view returns (bool) {
        return block.timestamp >= optionParameters.expiration;
    }

    /**
     * @notice Checks if there is a winner and returns the address of the winner.
     * @param _latestPrice The latest price from the feed.
     * @return The winner of the option.
     */
    function _isStrikePriceHit(int256 _latestPrice) internal view returns (bool) {
        if (optionParameters.optionType == OptionType.CALL) {
            // CALL means the option is won if the price is higher than the strike price
            if (_latestPrice >= optionParameters.strikePrice) {
                return true;
            }
        } else {
            // PUT means the option is won if the price is lower than the strike price
            if (_latestPrice <= optionParameters.strikePrice) {
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Allows the winner to withdraw the funds.
     */
    function withdraw(uint256 _amount) public {
        if (dealParameters.winner == address(0)) {
            revert ErrorOptionNotFinalized();
        }

        if (msg.sender != dealParameters.winner) {
            revert ErrorOnlyWinnerCanWithdraw();
        }

        if (_amount > address(this).balance) {
            revert ErrorInsufficientBalance();
        }

        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert ErrorWithdrawFailed();
        }

        emit OptionWithdrawn(dealParameters.winner, _amount);
    }

    /**
     * @notice Allows the seller to cancel the option if no one bought it yet.
     */
    function cancel() public {
        if (msg.sender != dealParameters.seller) {
            revert ErrorOnlySellerCanCancel();
        }

        if (dealParameters.buyer != address(0)) {
            revert ErrorOptionAlreadySold();
        }

        if (isCanceled) {
            revert ErrorOptionAlreadyCanceled();
        }

        dealParameters.winner = dealParameters.seller;
        isCanceled = true;

        emit OptionCanceled(dealParameters.seller, dealParameters.amount);
    }

    /**
     * @notice Returns the feed parameters.
     * @return The feed address and heartbeat.
     */
    function getFeedParameters() public view returns (address, uint256) {
        return (feedParameters.feed, feedParameters.heartbeat);
    }

    /**
     * @notice Returns the option parameters.
     * @return The option type, starting price, strike price, and expiration.
     */
    function getOptionParameters() public view returns (OptionType, int256, int256, uint256) {
        return (
            optionParameters.optionType,
            optionParameters.startingPrice,
            optionParameters.strikePrice,
            optionParameters.expiration
        );
    }

    /**
     * @notice Returns the deal parameters.
     * @return The buyer, seller, amount, and winner.
     */
    function getDealParameters() public view returns (address, address, uint256, address) {
        return (dealParameters.buyer, dealParameters.seller, dealParameters.amount, dealParameters.winner);
    }
}
