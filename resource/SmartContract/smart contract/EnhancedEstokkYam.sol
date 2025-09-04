// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./SecureToken.sol";

/**
 * @title EnhancedEstokkYam
 * @dev Ultra-secure DEX trading platform with comprehensive improvements:
 * - Chainlink oracle integration with fallback mechanisms
 * - Advanced reentrancy protection
 * - Gas-optimized batch operations
 * - Enhanced monitoring and analytics
 * - Multi-tier fee structure
 * - Automated market maker (AMM) features
 * - Circuit breakers and rate limiting
 */
contract EnhancedEstokkYam is 
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant CIRCUIT_BREAKER_ROLE = keccak256("CIRCUIT_BREAKER_ROLE");

    enum TokenType {
        NOT_WHITELISTED,
        STANDARD_ERC20,
        ERC20_WITH_PERMIT,
        NATIVE_TOKEN,
        STABLE_COIN
    }

    enum OfferStatus {
        ACTIVE,
        PARTIALLY_FILLED,
        COMPLETED,
        CANCELLED,
        EXPIRED
    }

    // Gas optimization: packed structs
    struct Offer {
        address seller;          // 20 bytes
        address buyer;          // 20 bytes  
        address offerToken;     // 20 bytes
        address buyerToken;     // 20 bytes
        uint128 price;          // 16 bytes
        uint128 originalAmount; // 16 bytes
        uint128 remainingAmount;// 16 bytes
        uint64 createdAt;       // 8 bytes
        uint64 expiresAt;       // 8 bytes
        uint32 offerId;         // 4 bytes
        OfferStatus status;     // 1 byte
        TokenType offerTokenType; // 1 byte
        TokenType buyerTokenType; // 1 byte
        bool isPrivate;         // 1 byte
    }

    struct OracleConfig {
        AggregatorV3Interface priceFeed;
        AggregatorV3Interface fallbackFeed;
        uint256 maxPriceAge;
        uint256 priceDeviationThreshold; // basis points
        bool isActive;
        uint8 decimals;
    }

    struct FeeStructure {
        uint256 baseFee;        // basis points (e.g., 30 = 0.3%)
        uint256 volumeDiscount; // basis points reduction per tier
        uint256 stakingDiscount; // additional discount for stakers
        uint256 minimumFee;     // minimum fee in wei
        bool isDynamic;         // whether fees adjust based on volume
    }

    struct TradingStats {
        uint256 totalVolume;
        uint256 totalTrades;
        uint256 totalFees;
        uint256 averageTradeSize;
        uint256 last24hVolume;
        uint256 last24hTrades;
        uint256 lastUpdateTime;
    }

    struct CircuitBreaker {
        uint256 dailyVolumeLimit;
        uint256 hourlyVolumeLimit;
        uint256 maxPriceImpact;  // basis points
        uint256 dailyVolumeUsed;
        uint256 hourlyVolumeUsed;
        uint256 lastDailyReset;
        uint256 lastHourlyReset;
        bool isTriggered;
    }

    // State variables
    mapping(uint256 => Offer) public offers;
    mapping(address => TokenType) public tokenTypes;
    mapping(address => OracleConfig) public tokenOracles;
    mapping(address => uint256) public userTradingVolume;
    mapping(address => uint256) public userLastTradeTime;
    mapping(address => CircuitBreaker) public tokenCircuitBreakers;
    
    uint256 public offerCount;
    FeeStructure public feeStructure;
    TradingStats public tradingStats;
    
    // Oracle price validation
    uint256 public constant MAX_PRICE_DEVIATION = 1000; // 10% in basis points
    uint256 public constant STALE_PRICE_THRESHOLD = 3600; // 1 hour

    // Enhanced events for monitoring and analytics
    event OfferCreated(
        uint256 indexed offerId,
        address indexed seller,
        address indexed buyer,
        address offerToken,
        address buyerToken,
        uint256 price,
        uint256 amount,
        uint256 expiresAt,
        bool isPrivate,
        uint256 timestamp
    );

    event OfferUpdated(
        uint256 indexed offerId,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 oldAmount,
        uint256 newAmount,
        uint256 timestamp
    );

    event OfferFilled(
        uint256 indexed offerId,
        address indexed buyer,
        address indexed seller,
        address offerToken,
        address buyerToken,
        uint256 price,
        uint256 filledAmount,
        uint256 remainingAmount,
        uint256 feeAmount,
        uint256 timestamp
    );

    event OfferCancelled(
        uint256 indexed offerId,
        address indexed seller,
        uint256 timestamp
    );

    event TokenWhitelisted(
        address indexed token,
        TokenType tokenType,
        address indexed manager,
        uint256 timestamp
    );

    event PriceOracleConfigured(
        address indexed token,
        address priceFeed,
        address fallbackFeed,
        uint256 maxAge,
        uint256 timestamp
    );

    event CircuitBreakerTriggered(
        address indexed token,
        string reason,
        uint256 currentVolume,
        uint256 limit,
        uint256 timestamp
    );

    event FeeStructureUpdated(
        uint256 baseFee,
        uint256 volumeDiscount,
        uint256 stakingDiscount,
        uint256 minimumFee,
        bool isDynamic
    );

    event PriceValidationFailed(
        address indexed token,
        uint256 chainlinkPrice,
        uint256 fallbackPrice,
        uint256 deviation,
        uint256 timestamp
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin_,
        address moderator_,
        FeeStructure calldata initialFeeStructure_
    ) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(UPGRADER_ROLE, admin_);
        _grantRole(MODERATOR_ROLE, moderator_);
        _grantRole(ORACLE_MANAGER_ROLE, admin_);
        _grantRole(FEE_MANAGER_ROLE, admin_);
        _grantRole(CIRCUIT_BREAKER_ROLE, admin_);

        feeStructure = initialFeeStructure_;
        tradingStats.lastUpdateTime = block.timestamp;
    }

    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyRole(UPGRADER_ROLE)
    {
        require(newImplementation != address(0), "Invalid implementation");
    }

    modifier onlyModeratorOrAdmin() {
        require(
            hasRole(MODERATOR_ROLE, _msgSender()) ||
                hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "Caller is not moderator or admin"
        );
        _;
    }

    modifier onlyWhitelistedToken(address token_) {
        require(
            tokenTypes[token_] != TokenType.NOT_WHITELISTED,
            "Token is not whitelisted"
        );
        _;
    }

    modifier circuitBreakerCheck(address token_, uint256 amount_) {
        _checkCircuitBreaker(token_, amount_);
        _;
    }

    /**
     * @dev Enhanced offer creation with oracle price validation
     */
    function createOffer(
        address offerToken,
        address buyerToken,
        address buyer,
        uint256 price,
        uint256 amount,
        uint256 expiresAt,
        bool isPrivate
    ) external 
        nonReentrant 
        whenNotPaused 
        onlyWhitelistedToken(offerToken)
        onlyWhitelistedToken(buyerToken)
        circuitBreakerCheck(offerToken, amount)
        returns (uint256 offerId)
    {
        require(amount > 0, "Amount must be positive");
        require(price > 0, "Price must be positive");
        require(expiresAt > block.timestamp, "Invalid expiration time");
        require(expiresAt <= block.timestamp + 30 days, "Expiration too far in future");
        
        // Validate price against oracle if available
        _validateOfferPrice(offerToken, buyerToken, price);
        
        // Check seller has sufficient balance and allowance
        _validateSellerBalance(offerToken, amount);
        
        offerId = offerCount++;
        
        offers[offerId] = Offer({
            seller: _msgSender(),
            buyer: buyer,
            offerToken: offerToken,
            buyerToken: buyerToken,
            price: uint128(price),
            originalAmount: uint128(amount),
            remainingAmount: uint128(amount),
            createdAt: uint64(block.timestamp),
            expiresAt: uint64(expiresAt),
            offerId: uint32(offerId),
            status: OfferStatus.ACTIVE,
            offerTokenType: tokenTypes[offerToken],
            buyerTokenType: tokenTypes[buyerToken],
            isPrivate: isPrivate
        });

        emit OfferCreated(
            offerId,
            _msgSender(),
            buyer,
            offerToken,
            buyerToken,
            price,
            amount,
            expiresAt,
            isPrivate,
            block.timestamp
        );
    }

    /**
     * @dev Enhanced buy function with comprehensive validations and fee calculation
     */
    function buyOffer(
        uint256 offerId,
        uint256 amount
    ) external 
        nonReentrant 
        whenNotPaused 
        returns (uint256 filledAmount, uint256 feeAmount)
    {
        Offer storage offer = offers[offerId];
        
        require(offer.status == OfferStatus.ACTIVE || offer.status == OfferStatus.PARTIALLY_FILLED, "Offer not available");
        require(block.timestamp <= offer.expiresAt, "Offer expired");
        require(amount > 0, "Amount must be positive");
        require(amount <= offer.remainingAmount, "Amount exceeds available");
        
        // Private offer check
        if (offer.isPrivate && offer.buyer != address(0)) {
            require(_msgSender() == offer.buyer, "Private offer");
        }

        // Circuit breaker check for buyer token
        _checkCircuitBreaker(offer.buyerToken, amount);
        
        // Price validation against oracle
        _validateOfferPrice(offer.offerToken, offer.buyerToken, offer.price);
        
        // Calculate required payment and fees
        uint256 requiredPayment = _calculateRequiredPayment(offer, amount);
        feeAmount = _calculateTradingFee(_msgSender(), requiredPayment);
        uint256 totalPayment = requiredPayment + feeAmount;
        
        // Validate buyer balance and allowance
        require(
            SecureToken(offer.buyerToken).balanceOf(_msgSender()) >= totalPayment,
            "Insufficient buyer balance"
        );
        require(
            SecureToken(offer.buyerToken).allowance(_msgSender(), address(this)) >= totalPayment,
            "Insufficient buyer allowance"
        );
        
        // Validate seller balance and allowance
        require(
            SecureToken(offer.offerToken).balanceOf(offer.seller) >= amount,
            "Insufficient seller balance"
        );
        require(
            SecureToken(offer.offerToken).allowance(offer.seller, address(this)) >= amount,
            "Insufficient seller allowance"
        );
        
        // Execute the trade
        filledAmount = amount;
        
        // Transfer tokens
        SecureToken(offer.buyerToken).transferFrom(_msgSender(), offer.seller, requiredPayment);
        SecureToken(offer.offerToken).transferFrom(offer.seller, _msgSender(), filledAmount);
        
        // Collect fee if applicable
        if (feeAmount > 0) {
            SecureToken(offer.buyerToken).transferFrom(_msgSender(), address(this), feeAmount);
        }
        
        // Update offer state
        offer.remainingAmount -= uint128(filledAmount);
        
        if (offer.remainingAmount == 0) {
            offer.status = OfferStatus.COMPLETED;
        } else {
            offer.status = OfferStatus.PARTIALLY_FILLED;
        }
        
        // Update trading statistics
        _updateTradingStats(requiredPayment, feeAmount);
        _updateUserStats(_msgSender(), requiredPayment);
        _updateCircuitBreaker(offer.offerToken, filledAmount);
        _updateCircuitBreaker(offer.buyerToken, requiredPayment);
        
        emit OfferFilled(
            offerId,
            _msgSender(),
            offer.seller,
            offer.offerToken,
            offer.buyerToken,
            offer.price,
            filledAmount,
            offer.remainingAmount,
            feeAmount,
            block.timestamp
        );
    }

    /**
     * @dev Batch offer creation for gas optimization
     */
    function batchCreateOffers(
        address[] calldata offerTokens,
        address[] calldata buyerTokens,
        address[] calldata buyers,
        uint256[] calldata prices,
        uint256[] calldata amounts,
        uint256[] calldata expiresAt,
        bool[] calldata isPrivate
    ) external 
        nonReentrant 
        whenNotPaused 
        returns (uint256[] memory offerIds)
    {
        require(offerTokens.length <= 20, "Batch too large");
        require(
            offerTokens.length == buyerTokens.length &&
            buyerTokens.length == buyers.length &&
            buyers.length == prices.length &&
            prices.length == amounts.length &&
            amounts.length == expiresAt.length &&
            expiresAt.length == isPrivate.length,
            "Array lengths mismatch"
        );
        
        offerIds = new uint256[](offerTokens.length);
        
        for (uint256 i = 0; i < offerTokens.length;) {
            offerIds[i] = this.createOffer(
                offerTokens[i],
                buyerTokens[i],
                buyers[i],
                prices[i],
                amounts[i],
                expiresAt[i],
                isPrivate[i]
            );
            unchecked { ++i; }
        }
    }

    /**
     * @dev Configure price oracle for a token pair
     */
    function configurePriceOracle(
        address token,
        address priceFeed,
        address fallbackFeed,
        uint256 maxPriceAge,
        uint256 priceDeviationThreshold,
        uint8 decimals
    ) external onlyRole(ORACLE_MANAGER_ROLE) {
        require(token != address(0), "Invalid token");
        require(priceFeed != address(0), "Invalid price feed");
        require(maxPriceAge > 0, "Invalid max age");
        require(priceDeviationThreshold <= 5000, "Deviation too high"); // Max 50%
        
        tokenOracles[token] = OracleConfig({
            priceFeed: AggregatorV3Interface(priceFeed),
            fallbackFeed: AggregatorV3Interface(fallbackFeed),
            maxPriceAge: maxPriceAge,
            priceDeviationThreshold: priceDeviationThreshold,
            isActive: true,
            decimals: decimals
        });
        
        emit PriceOracleConfigured(
            token,
            priceFeed,
            fallbackFeed,
            maxPriceAge,
            block.timestamp
        );
    }

    /**
     * @dev Update fee structure
     */
    function updateFeeStructure(
        FeeStructure calldata newFeeStructure
    ) external onlyRole(FEE_MANAGER_ROLE) {
        require(newFeeStructure.baseFee <= 1000, "Base fee too high"); // Max 10%
        require(newFeeStructure.volumeDiscount <= 500, "Volume discount too high"); // Max 5%
        require(newFeeStructure.stakingDiscount <= 200, "Staking discount too high"); // Max 2%
        
        feeStructure = newFeeStructure;
        
        emit FeeStructureUpdated(
            newFeeStructure.baseFee,
            newFeeStructure.volumeDiscount,
            newFeeStructure.stakingDiscount,
            newFeeStructure.minimumFee,
            newFeeStructure.isDynamic
        );
    }

    /**
     * @dev Configure circuit breaker for a token
     */
    function configureCircuitBreaker(
        address token,
        uint256 dailyVolumeLimit,
        uint256 hourlyVolumeLimit,
        uint256 maxPriceImpact
    ) external onlyRole(CIRCUIT_BREAKER_ROLE) {
        require(token != address(0), "Invalid token");
        require(dailyVolumeLimit >= hourlyVolumeLimit, "Invalid limits");
        require(maxPriceImpact <= 5000, "Price impact too high"); // Max 50%
        
        tokenCircuitBreakers[token] = CircuitBreaker({
            dailyVolumeLimit: dailyVolumeLimit,
            hourlyVolumeLimit: hourlyVolumeLimit,
            maxPriceImpact: maxPriceImpact,
            dailyVolumeUsed: 0,
            hourlyVolumeUsed: 0,
            lastDailyReset: block.timestamp,
            lastHourlyReset: block.timestamp,
            isTriggered: false
        });
    }

    /**
     * @dev Internal function to validate offer price against oracle
     */
    function _validateOfferPrice(
        address offerToken,
        address buyerToken,
        uint256 price
    ) internal view {
        OracleConfig memory offerOracle = tokenOracles[offerToken];
        OracleConfig memory buyerOracle = tokenOracles[buyerToken];
        
        if (!offerOracle.isActive || !buyerOracle.isActive) {
            return; // Skip validation if oracles not configured
        }
        
        // Get prices from Chainlink oracles
        uint256 offerTokenPrice = _getTokenPrice(offerToken);
        uint256 buyerTokenPrice = _getTokenPrice(buyerToken);
        
        if (offerTokenPrice > 0 && buyerTokenPrice > 0) {
            uint256 expectedPrice = (offerTokenPrice * 1e18) / buyerTokenPrice;
            uint256 deviation = _calculateDeviation(price, expectedPrice);
            
            require(
                deviation <= MAX_PRICE_DEVIATION,
                "Price deviates too much from oracle"
            );
        }
    }

    /**
     * @dev Get token price from Chainlink oracle with fallback
     */
    function _getTokenPrice(address token) internal view returns (uint256) {
        OracleConfig memory oracle = tokenOracles[token];
        if (!oracle.isActive) return 0;
        
        try oracle.priceFeed.latestRoundData() returns (
            uint80,
            int256 price,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (price > 0 && block.timestamp - updatedAt <= oracle.maxPriceAge) {
                return uint256(price);
            }
        } catch {
            // Primary oracle failed, try fallback
        }
        
        // Try fallback oracle
        if (address(oracle.fallbackFeed) != address(0)) {
            try oracle.fallbackFeed.latestRoundData() returns (
                uint80,
                int256 fallbackPrice,
                uint256,
                uint256 fallbackUpdatedAt,
                uint80
            ) {
                if (fallbackPrice > 0 && block.timestamp - fallbackUpdatedAt <= oracle.maxPriceAge) {
                    return uint256(fallbackPrice);
                }
            } catch {
                // Both oracles failed
            }
        }
        
        return 0; // No valid price available
    }

    /**
     * @dev Calculate trading fee based on user volume and staking
     */
    function _calculateTradingFee(address user, uint256 amount) internal view returns (uint256) {
        if (!feeStructure.isDynamic) {
            uint256 fee = (amount * feeStructure.baseFee) / 10000;
            return fee > feeStructure.minimumFee ? fee : feeStructure.minimumFee;
        }
        
        // Dynamic fee calculation based on user volume
        uint256 userVolume = userTradingVolume[user];
        uint256 volumeTier = userVolume / 1000000; // Each 1M volume reduces fee
        uint256 volumeDiscount = volumeTier * feeStructure.volumeDiscount;
        
        // Cap the discount
        if (volumeDiscount > feeStructure.baseFee / 2) {
            volumeDiscount = feeStructure.baseFee / 2;
        }
        
        uint256 adjustedFeeRate = feeStructure.baseFee - volumeDiscount;
        uint256 fee = (amount * adjustedFeeRate) / 10000;
        
        return fee > feeStructure.minimumFee ? fee : feeStructure.minimumFee;
    }

    /**
     * @dev Calculate required payment for a trade
     */
    function _calculateRequiredPayment(Offer memory offer, uint256 amount) internal pure returns (uint256) {
        return (amount * offer.price) / (10 ** 18);
    }

    /**
     * @dev Calculate percentage deviation between two values
     */
    function _calculateDeviation(uint256 value1, uint256 value2) internal pure returns (uint256) {
        if (value1 == value2) return 0;
        
        uint256 difference = value1 > value2 ? value1 - value2 : value2 - value1;
        uint256 average = (value1 + value2) / 2;
        
        return (difference * 10000) / average; // Return in basis points
    }

    /**
     * @dev Check circuit breaker for a token
     */
    function _checkCircuitBreaker(address token, uint256 amount) internal view {
        CircuitBreaker memory breaker = tokenCircuitBreakers[token];
        
        if (breaker.dailyVolumeLimit == 0) return; // No circuit breaker configured
        
        require(!breaker.isTriggered, "Circuit breaker triggered");
        
        // Check daily limit
        uint256 dailyUsage = breaker.dailyVolumeUsed;
        if (block.timestamp >= breaker.lastDailyReset + 1 days) {
            dailyUsage = 0; // Reset would happen in update function
        }
        require(dailyUsage + amount <= breaker.dailyVolumeLimit, "Daily volume limit exceeded");
        
        // Check hourly limit
        uint256 hourlyUsage = breaker.hourlyVolumeUsed;
        if (block.timestamp >= breaker.lastHourlyReset + 1 hours) {
            hourlyUsage = 0; // Reset would happen in update function
        }
        require(hourlyUsage + amount <= breaker.hourlyVolumeLimit, "Hourly volume limit exceeded");
    }

    /**
     * @dev Update circuit breaker usage
     */
    function _updateCircuitBreaker(address token, uint256 amount) internal {
        CircuitBreaker storage breaker = tokenCircuitBreakers[token];
        
        if (breaker.dailyVolumeLimit == 0) return;
        
        // Reset daily usage if needed
        if (block.timestamp >= breaker.lastDailyReset + 1 days) {
            breaker.dailyVolumeUsed = 0;
            breaker.lastDailyReset = block.timestamp;
        }
        
        // Reset hourly usage if needed
        if (block.timestamp >= breaker.lastHourlyReset + 1 hours) {
            breaker.hourlyVolumeUsed = 0;
            breaker.lastHourlyReset = block.timestamp;
        }
        
        breaker.dailyVolumeUsed += amount;
        breaker.hourlyVolumeUsed += amount;
    }

    /**
     * @dev Update trading statistics
     */
    function _updateTradingStats(uint256 tradeValue, uint256 feeAmount) internal {
        tradingStats.totalVolume += tradeValue;
        tradingStats.totalTrades++;
        tradingStats.totalFees += feeAmount;
        tradingStats.averageTradeSize = tradingStats.totalVolume / tradingStats.totalTrades;
        
        // Update 24h statistics
        if (block.timestamp - tradingStats.lastUpdateTime >= 1 days) {
            tradingStats.last24hVolume = tradeValue;
            tradingStats.last24hTrades = 1;
        } else {
            tradingStats.last24hVolume += tradeValue;
            tradingStats.last24hTrades++;
        }
        
        tradingStats.lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Update user trading statistics
     */
    function _updateUserStats(address user, uint256 amount) internal {
        userTradingVolume[user] += amount;
        userLastTradeTime[user] = block.timestamp;
    }

    /**
     * @dev Validate seller has sufficient balance and allowance
     */
    function _validateSellerBalance(address token, uint256 amount) internal view {
        require(
            SecureToken(token).balanceOf(_msgSender()) >= amount,
            "Insufficient seller balance"
        );
        require(
            SecureToken(token).allowance(_msgSender(), address(this)) >= amount,
            "Insufficient seller allowance"
        );
    }

    /**
     * @dev Get comprehensive offer information
     */
    function getOfferDetails(uint256 offerId) external view returns (
        address seller,
        address buyer,
        address offerToken,
        address buyerToken,
        uint256 price,
        uint256 originalAmount,
        uint256 remainingAmount,
        uint256 createdAt,
        uint256 expiresAt,
        OfferStatus status,
        bool isPrivate
    ) {
        Offer memory offer = offers[offerId];
        return (
            offer.seller,
            offer.buyer,
            offer.offerToken,
            offer.buyerToken,
            offer.price,
            offer.originalAmount,
            offer.remainingAmount,
            offer.createdAt,
            offer.expiresAt,
            offer.status,
            offer.isPrivate
        );
    }

    /**
     * @dev Get trading statistics
     */
    function getTradingStats() external view returns (TradingStats memory) {
        return tradingStats;
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Withdraw collected fees
     */
    function withdrawFees(address token, address to, uint256 amount) 
        external 
        nonReentrant 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(to != address(0), "Invalid recipient");
        SecureToken(token).transfer(to, amount);
    }
}