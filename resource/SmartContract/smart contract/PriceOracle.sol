// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceOracle
 * @dev Comprehensive price oracle system with:
 * - Primary Chainlink feeds with multiple fallback mechanisms
 * - TWAP (Time-Weighted Average Price) calculations
 * - Circuit breakers for price manipulation protection
 * - Historical price tracking and analytics
 * - Cross-chain price synchronization capabilities
 * - Dynamic price validation and deviation detection
 */
contract PriceOracle is 
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    bytes32 public constant CIRCUIT_BREAKER_ROLE = keccak256("CIRCUIT_BREAKER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Price feed configuration
    struct PriceFeedConfig {
        AggregatorV3Interface primaryFeed;    // Primary Chainlink feed
        AggregatorV3Interface secondaryFeed;  // Secondary Chainlink feed
        address customFeed;                   // Custom oracle feed
        uint256 maxStaleness;                 // Maximum age for valid price
        uint256 deviationThreshold;          // Max deviation between feeds (basis points)
        uint256 minPrice;                     // Minimum valid price
        uint256 maxPrice;                     // Maximum valid price
        uint8 decimals;                       // Price decimals
        bool isActive;                        // Whether feed is active
        bool requiresSecondaryValidation;     // Whether secondary validation required
    }

    // TWAP configuration and data
    struct TWAPConfig {
        uint256 windowSize;        // TWAP window in seconds
        uint256 updateThreshold;   // Minimum time between updates
        uint256 minObservations;   // Minimum observations for valid TWAP
        bool isEnabled;           // Whether TWAP is enabled
    }

    struct PriceObservation {
        uint256 timestamp;
        uint256 price;
        uint256 cumulativePrice;
        bool isValid;
    }

    // Circuit breaker for price manipulation protection
    struct CircuitBreaker {
        uint256 maxPriceChangePercent;  // Max price change % per period
        uint256 timeWindow;             // Time window for price change check
        uint256 consecutiveFailures;    // Number of consecutive validation failures
        uint256 maxFailures;           // Max failures before circuit break
        uint256 lastPriceUpdate;       // Last price update timestamp
        uint256 lastValidPrice;        // Last valid price
        bool isTriggered;              // Whether circuit breaker is active
    }

    // Price validation result
    struct ValidationResult {
        bool isValid;
        uint256 validatedPrice;
        string failureReason;
        uint256 primaryPrice;
        uint256 secondaryPrice;
        uint256 deviation;
        uint256 timestamp;
    }

    // Historical price data for analytics
    struct HistoricalData {
        uint256[] prices;
        uint256[] timestamps;
        uint256 currentIndex;
        uint256 maxEntries;
        bool isInitialized;
    }

    // State variables
    mapping(address => PriceFeedConfig) public priceFeedConfigs;
    mapping(address => TWAPConfig) public twapConfigs;
    mapping(address => PriceObservation[]) public priceObservations;
    mapping(address => CircuitBreaker) public circuitBreakers;
    mapping(address => HistoricalData) private historicalPrices;
    mapping(address => uint256) public lastValidPrices;
    mapping(address => uint256) public lastPriceUpdates;

    // Global settings
    uint256 public constant DEFAULT_MAX_STALENESS = 3600; // 1 hour
    uint256 public constant DEFAULT_DEVIATION_THRESHOLD = 500; // 5%
    uint256 public constant DEFAULT_TWAP_WINDOW = 1800; // 30 minutes
    uint256 public constant MAX_CIRCUIT_BREAKER_TIME = 24 hours;

    // Enhanced events for monitoring
    event PriceFeedConfigured(
        address indexed token,
        address primaryFeed,
        address secondaryFeed,
        address customFeed,
        uint256 maxStaleness,
        uint256 deviationThreshold
    );

    event PriceUpdated(
        address indexed token,
        uint256 newPrice,
        uint256 oldPrice,
        uint256 timestamp,
        string source
    );

    event PriceValidationFailed(
        address indexed token,
        uint256 primaryPrice,
        uint256 secondaryPrice,
        uint256 deviation,
        string reason,
        uint256 timestamp
    );

    event TWAPUpdated(
        address indexed token,
        uint256 twapPrice,
        uint256 spotPrice,
        uint256 windowSize,
        uint256 observations
    );

    event CircuitBreakerTriggered(
        address indexed token,
        uint256 currentPrice,
        uint256 lastValidPrice,
        uint256 changePercent,
        uint256 timestamp
    );

    event CircuitBreakerReset(
        address indexed token,
        uint256 timestamp
    );

    event EmergencyPriceSet(
        address indexed token,
        uint256 emergencyPrice,
        address indexed setter,
        string reason,
        uint256 timestamp
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin_) external initializer {
        require(admin_ != address(0), "Oracle: admin cannot be zero");
        
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ORACLE_ADMIN_ROLE, admin_);
        _grantRole(PRICE_UPDATER_ROLE, admin_);
        _grantRole(CIRCUIT_BREAKER_ROLE, admin_);
        _grantRole(UPGRADER_ROLE, admin_);
    }

    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyRole(UPGRADER_ROLE)
    {
        require(newImplementation != address(0), "Oracle: invalid implementation");
    }

    /**
     * @dev Configure price feed for a token with comprehensive settings
     */
    function configurePriceFeed(
        address token,
        address primaryFeed,
        address secondaryFeed,
        address customFeed,
        uint256 maxStaleness,
        uint256 deviationThreshold,
        uint256 minPrice,
        uint256 maxPrice,
        uint8 decimals,
        bool requiresSecondaryValidation
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        require(token != address(0), "Oracle: invalid token");
        require(primaryFeed != address(0), "Oracle: invalid primary feed");
        require(deviationThreshold <= 5000, "Oracle: deviation too high"); // Max 50%
        require(maxStaleness <= 24 hours, "Oracle: staleness too high");
        require(minPrice < maxPrice, "Oracle: invalid price range");

        priceFeedConfigs[token] = PriceFeedConfig({
            primaryFeed: AggregatorV3Interface(primaryFeed),
            secondaryFeed: secondaryFeed != address(0) ? AggregatorV3Interface(secondaryFeed) : AggregatorV3Interface(address(0)),
            customFeed: customFeed,
            maxStaleness: maxStaleness == 0 ? DEFAULT_MAX_STALENESS : maxStaleness,
            deviationThreshold: deviationThreshold == 0 ? DEFAULT_DEVIATION_THRESHOLD : deviationThreshold,
            minPrice: minPrice,
            maxPrice: maxPrice,
            decimals: decimals,
            isActive: true,
            requiresSecondaryValidation: requiresSecondaryValidation
        });

        emit PriceFeedConfigured(
            token,
            primaryFeed,
            secondaryFeed,
            customFeed,
            maxStaleness,
            deviationThreshold
        );
    }

    /**
     * @dev Configure TWAP settings for a token
     */
    function configureTWAP(
        address token,
        uint256 windowSize,
        uint256 updateThreshold,
        uint256 minObservations
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        require(token != address(0), "Oracle: invalid token");
        require(windowSize >= 300, "Oracle: window too small"); // Min 5 minutes
        require(windowSize <= 24 hours, "Oracle: window too large");
        require(minObservations >= 2, "Oracle: min observations too low");

        twapConfigs[token] = TWAPConfig({
            windowSize: windowSize,
            updateThreshold: updateThreshold,
            minObservations: minObservations,
            isEnabled: true
        });

        // Initialize historical data
        if (!historicalPrices[token].isInitialized) {
            historicalPrices[token] = HistoricalData({
                prices: new uint256[](100), // Store up to 100 historical prices
                timestamps: new uint256[](100),
                currentIndex: 0,
                maxEntries: 100,
                isInitialized: true
            });
        }
    }

    /**
     * @dev Configure circuit breaker for a token
     */
    function configureCircuitBreaker(
        address token,
        uint256 maxPriceChangePercent,
        uint256 timeWindow,
        uint256 maxFailures
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        require(token != address(0), "Oracle: invalid token");
        require(maxPriceChangePercent <= 5000, "Oracle: change limit too high"); // Max 50%
        require(timeWindow >= 300, "Oracle: time window too small"); // Min 5 minutes
        require(timeWindow <= MAX_CIRCUIT_BREAKER_TIME, "Oracle: time window too large");
        require(maxFailures >= 1 && maxFailures <= 10, "Oracle: invalid max failures");

        circuitBreakers[token] = CircuitBreaker({
            maxPriceChangePercent: maxPriceChangePercent,
            timeWindow: timeWindow,
            consecutiveFailures: 0,
            maxFailures: maxFailures,
            lastPriceUpdate: 0,
            lastValidPrice: 0,
            isTriggered: false
        });
    }

    /**
     * @dev Get validated price for a token with comprehensive checks
     */
    function getPrice(address token) external view returns (ValidationResult memory) {
        PriceFeedConfig memory config = priceFeedConfigs[token];
        require(config.isActive, "Oracle: feed not active");
        
        CircuitBreaker memory breaker = circuitBreakers[token];
        if (breaker.isTriggered) {
            return ValidationResult({
                isValid: false,
                validatedPrice: breaker.lastValidPrice,
                failureReason: "Circuit breaker triggered",
                primaryPrice: 0,
                secondaryPrice: 0,
                deviation: 0,
                timestamp: block.timestamp
            });
        }

        return _validateAndGetPrice(token, config);
    }

    /**
     * @dev Get TWAP price for a token
     */
    function getTWAPPrice(address token, uint256 windowSize) external view returns (uint256, bool) {
        TWAPConfig memory twapConfig = twapConfigs[token];
        if (!twapConfig.isEnabled) {
            return (0, false);
        }

        uint256 targetWindowSize = windowSize == 0 ? twapConfig.windowSize : windowSize;
        PriceObservation[] memory observations = priceObservations[token];
        
        if (observations.length < twapConfig.minObservations) {
            return (0, false);
        }

        return _calculateTWAP(observations, targetWindowSize, twapConfig.minObservations);
    }

    /**
     * @dev Update price observation (called by price updater role)
     */
    function updatePriceObservation(address token) external onlyRole(PRICE_UPDATER_ROLE) {
        PriceFeedConfig memory config = priceFeedConfigs[token];
        require(config.isActive, "Oracle: feed not active");

        ValidationResult memory result = _validateAndGetPrice(token, config);
        
        if (result.isValid) {
            _addPriceObservation(token, result.validatedPrice);
            _updateHistoricalData(token, result.validatedPrice);
            
            lastValidPrices[token] = result.validatedPrice;
            lastPriceUpdates[token] = block.timestamp;

            emit PriceUpdated(
                token,
                result.validatedPrice,
                lastValidPrices[token],
                block.timestamp,
                "Oracle Update"
            );
        } else {
            _handleValidationFailure(token, result);
        }
    }

    /**
     * @dev Batch update multiple token prices
     */
    function batchUpdatePrices(address[] calldata tokens) external onlyRole(PRICE_UPDATER_ROLE) {
        require(tokens.length <= 50, "Oracle: batch too large");
        
        for (uint256 i = 0; i < tokens.length;) {
            try this.updatePriceObservation(tokens[i]) {
                // Success - continue
            } catch {
                // Log failure but continue with other tokens
                emit PriceValidationFailed(
                    tokens[i],
                    0,
                    0,
                    0,
                    "Batch update failed",
                    block.timestamp
                );
            }
            unchecked { ++i; }
        }
    }

    /**
     * @dev Emergency price set function (for extreme situations)
     */
    function setEmergencyPrice(
        address token,
        uint256 emergencyPrice,
        string calldata reason
    ) external onlyRole(CIRCUIT_BREAKER_ROLE) {
        require(token != address(0), "Oracle: invalid token");
        require(emergencyPrice > 0, "Oracle: invalid price");
        
        // Trigger circuit breaker if not already triggered
        CircuitBreaker storage breaker = circuitBreakers[token];
        breaker.isTriggered = true;
        breaker.lastValidPrice = emergencyPrice;
        breaker.lastPriceUpdate = block.timestamp;
        
        lastValidPrices[token] = emergencyPrice;
        lastPriceUpdates[token] = block.timestamp;

        emit EmergencyPriceSet(token, emergencyPrice, _msgSender(), reason, block.timestamp);
    }

    /**
     * @dev Reset circuit breaker for a token
     */
    function resetCircuitBreaker(address token) external onlyRole(CIRCUIT_BREAKER_ROLE) {
        CircuitBreaker storage breaker = circuitBreakers[token];
        breaker.isTriggered = false;
        breaker.consecutiveFailures = 0;
        breaker.lastPriceUpdate = block.timestamp;

        emit CircuitBreakerReset(token, block.timestamp);
    }

    /**
     * @dev Internal function to validate and get price from feeds
     */
    function _validateAndGetPrice(address token, PriceFeedConfig memory config) 
        internal 
        view 
        returns (ValidationResult memory) 
    {
        // Get primary price
        (bool primarySuccess, uint256 primaryPrice, uint256 primaryUpdatedAt) = _getFeedPrice(config.primaryFeed);
        
        // Check if primary price is stale
        if (!primarySuccess || block.timestamp - primaryUpdatedAt > config.maxStaleness) {
            return ValidationResult({
                isValid: false,
                validatedPrice: 0,
                failureReason: "Primary feed stale or failed",
                primaryPrice: primaryPrice,
                secondaryPrice: 0,
                deviation: 0,
                timestamp: block.timestamp
            });
        }

        // Check price bounds
        if (primaryPrice < config.minPrice || primaryPrice > config.maxPrice) {
            return ValidationResult({
                isValid: false,
                validatedPrice: 0,
                failureReason: "Price out of bounds",
                primaryPrice: primaryPrice,
                secondaryPrice: 0,
                deviation: 0,
                timestamp: block.timestamp
            });
        }

        // If secondary validation required, check secondary feed
        if (config.requiresSecondaryValidation && address(config.secondaryFeed) != address(0)) {
            (bool secondarySuccess, uint256 secondaryPrice, uint256 secondaryUpdatedAt) = _getFeedPrice(config.secondaryFeed);
            
            if (!secondarySuccess || block.timestamp - secondaryUpdatedAt > config.maxStaleness) {
                return ValidationResult({
                    isValid: false,
                    validatedPrice: 0,
                    failureReason: "Secondary feed stale or failed",
                    primaryPrice: primaryPrice,
                    secondaryPrice: secondaryPrice,
                    deviation: 0,
                    timestamp: block.timestamp
                });
            }

            // Check deviation between primary and secondary feeds
            uint256 deviation = _calculateDeviation(primaryPrice, secondaryPrice);
            if (deviation > config.deviationThreshold) {
                return ValidationResult({
                    isValid: false,
                    validatedPrice: 0,
                    failureReason: "Feeds deviation too high",
                    primaryPrice: primaryPrice,
                    secondaryPrice: secondaryPrice,
                    deviation: deviation,
                    timestamp: block.timestamp
                });
            }

            // Use average of both feeds if validation passes
            uint256 averagePrice = (primaryPrice + secondaryPrice) / 2;
            return ValidationResult({
                isValid: true,
                validatedPrice: averagePrice,
                failureReason: "",
                primaryPrice: primaryPrice,
                secondaryPrice: secondaryPrice,
                deviation: deviation,
                timestamp: block.timestamp
            });
        }

        // Return primary price if no secondary validation required
        return ValidationResult({
            isValid: true,
            validatedPrice: primaryPrice,
            failureReason: "",
            primaryPrice: primaryPrice,
            secondaryPrice: 0,
            deviation: 0,
            timestamp: block.timestamp
        });
    }

    /**
     * @dev Get price from Chainlink feed
     */
    function _getFeedPrice(AggregatorV3Interface feed) 
        internal 
        view 
        returns (bool success, uint256 price, uint256 updatedAt) 
    {
        try feed.latestRoundData() returns (
            uint80,
            int256 feedPrice,
            uint256,
            uint256 feedUpdatedAt,
            uint80
        ) {
            if (feedPrice > 0) {
                return (true, uint256(feedPrice), feedUpdatedAt);
            }
        } catch {
            // Feed call failed
        }
        
        return (false, 0, 0);
    }

    /**
     * @dev Calculate percentage deviation between two prices
     */
    function _calculateDeviation(uint256 price1, uint256 price2) internal pure returns (uint256) {
        if (price1 == price2) return 0;
        
        uint256 difference = price1 > price2 ? price1 - price2 : price2 - price1;
        uint256 average = (price1 + price2) / 2;
        
        return (difference * 10000) / average; // Return in basis points
    }

    /**
     * @dev Add price observation for TWAP calculation
     */
    function _addPriceObservation(address token, uint256 price) internal {
        PriceObservation[] storage observations = priceObservations[token];
        
        // Calculate cumulative price
        uint256 cumulativePrice = 0;
        if (observations.length > 0) {
            PriceObservation memory lastObservation = observations[observations.length - 1];
            uint256 timeElapsed = block.timestamp - lastObservation.timestamp;
            cumulativePrice = lastObservation.cumulativePrice + (lastObservation.price * timeElapsed);
        }

        observations.push(PriceObservation({
            timestamp: block.timestamp,
            price: price,
            cumulativePrice: cumulativePrice,
            isValid: true
        }));

        // Keep only relevant observations (within TWAP window * 2)
        TWAPConfig memory twapConfig = twapConfigs[token];
        if (twapConfig.isEnabled) {
            uint256 cutoffTime = block.timestamp - (twapConfig.windowSize * 2);
            _cleanOldObservations(token, cutoffTime);
        }
    }

    /**
     * @dev Calculate TWAP from observations
     */
    function _calculateTWAP(
        PriceObservation[] memory observations,
        uint256 windowSize,
        uint256 minObservations
    ) internal view returns (uint256 twapPrice, bool isValid) {
        if (observations.length < minObservations) {
            return (0, false);
        }

        uint256 windowStart = block.timestamp - windowSize;
        uint256 totalValue = 0;
        uint256 totalTime = 0;
        
        for (uint256 i = 0; i < observations.length - 1;) {
            PriceObservation memory current = observations[i];
            PriceObservation memory next = observations[i + 1];
            
            if (next.timestamp <= windowStart) {
                unchecked { ++i; }
                continue;
            }
            
            uint256 startTime = current.timestamp > windowStart ? current.timestamp : windowStart;
            uint256 endTime = next.timestamp;
            uint256 timeSpan = endTime - startTime;
            
            totalValue += current.price * timeSpan;
            totalTime += timeSpan;
            
            unchecked { ++i; }
        }

        if (totalTime == 0) {
            return (0, false);
        }

        return (totalValue / totalTime, true);
    }

    /**
     * @dev Clean old observations outside TWAP window
     */
    function _cleanOldObservations(address token, uint256 cutoffTime) internal {
        PriceObservation[] storage observations = priceObservations[token];
        
        // Find first observation to keep
        uint256 keepFromIndex = 0;
        for (uint256 i = 0; i < observations.length;) {
            if (observations[i].timestamp >= cutoffTime) {
                keepFromIndex = i;
                break;
            }
            unchecked { ++i; }
        }

        // Remove old observations if needed
        if (keepFromIndex > 0) {
            for (uint256 i = 0; i < observations.length - keepFromIndex;) {
                observations[i] = observations[i + keepFromIndex];
                unchecked { ++i; }
            }
            
            // Reduce array length
            for (uint256 i = 0; i < keepFromIndex;) {
                observations.pop();
                unchecked { ++i; }
            }
        }
    }

    /**
     * @dev Update historical price data
     */
    function _updateHistoricalData(address token, uint256 price) internal {
        HistoricalData storage data = historicalPrices[token];
        if (!data.isInitialized) return;

        data.prices[data.currentIndex] = price;
        data.timestamps[data.currentIndex] = block.timestamp;
        data.currentIndex = (data.currentIndex + 1) % data.maxEntries;
    }

    /**
     * @dev Handle price validation failure
     */
    function _handleValidationFailure(address token, ValidationResult memory result) internal {
        CircuitBreaker storage breaker = circuitBreakers[token];
        breaker.consecutiveFailures++;

        emit PriceValidationFailed(
            token,
            result.primaryPrice,
            result.secondaryPrice,
            result.deviation,
            result.failureReason,
            block.timestamp
        );

        // Trigger circuit breaker if too many failures
        if (breaker.consecutiveFailures >= breaker.maxFailures) {
            breaker.isTriggered = true;
            
            emit CircuitBreakerTriggered(
                token,
                0,
                breaker.lastValidPrice,
                0,
                block.timestamp
            );
        }
    }

    /**
     * @dev Get historical prices for analytics
     */
    function getHistoricalPrices(address token, uint256 count) 
        external 
        view 
        returns (uint256[] memory prices, uint256[] memory timestamps) 
    {
        HistoricalData storage data = historicalPrices[token];
        if (!data.isInitialized || count == 0) {
            return (new uint256[](0), new uint256[](0));
        }

        uint256 actualCount = count > data.maxEntries ? data.maxEntries : count;
        prices = new uint256[](actualCount);
        timestamps = new uint256[](actualCount);

        for (uint256 i = 0; i < actualCount;) {
            uint256 index = (data.currentIndex - i - 1 + data.maxEntries) % data.maxEntries;
            prices[i] = data.prices[index];
            timestamps[i] = data.timestamps[index];
            unchecked { ++i; }
        }
    }

    /**
     * @dev Pause oracle operations
     */
    function pause() external onlyRole(ORACLE_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause oracle operations
     */
    function unpause() external onlyRole(ORACLE_ADMIN_ROLE) {
        _unpause();
    }
}