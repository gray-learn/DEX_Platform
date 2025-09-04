// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SecureToken.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title SecureTokenFactory
 * @dev Gas-optimized, secure token factory with:
 * - CREATE2 deterministic deployment
 * - Role-based access control
 * - Reentrancy protection
 * - Gas-optimized batch operations
 * - Comprehensive event logging
 * - Emergency pause functionality
 */
contract SecureTokenFactory is 
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant FACTORY_ADMIN_ROLE = keccak256("FACTORY_ADMIN_ROLE");
    bytes32 public constant TOKEN_CREATOR_ROLE = keccak256("TOKEN_CREATOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // Gas optimization: pack deployment parameters
    struct DeploymentParams {
        string name;
        string symbol;
        uint8 decimals;
        uint256 cap;
        uint256 initialSupply;
        uint256 salt;
        address admin;
    }
    
    // Gas optimization: pack factory statistics
    struct FactoryStats {
        uint128 totalTokensCreated;     // 16 bytes
        uint128 activeTokens;           // 16 bytes (fits in one storage slot)
        uint256 totalGasUsed;           // 32 bytes
        uint256 lastDeploymentTime;     // 32 bytes
    }
    
    FactoryStats public factoryStats;
    
    // Store deployed token addresses with metadata
    mapping(uint256 => address) public deployedTokens;
    mapping(address => bool) public isFactoryToken;
    mapping(address => uint256) public tokenCreationTime;
    mapping(bytes32 => address) public saltToAddress;
    
    // Fee structure for token creation
    uint256 public creationFee;
    address public feeRecipient;
    
    // Token implementation address for proxy deployments
    address public tokenImplementation;
    
    // Enhanced events for monitoring and analytics
    event TokenCreated(
        address indexed tokenAddress,
        address indexed creator,
        string name,
        string symbol,
        uint8 decimals,
        uint256 cap,
        uint256 initialSupply,
        uint256 salt,
        uint256 gasUsed,
        uint256 timestamp
    );
    
    event TokenBurned(
        address indexed tokenAddress,
        address indexed burner,
        uint256 amount,
        uint256 timestamp
    );
    
    event FactoryFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event TokenImplementationUpdated(address oldImpl, address newImpl);
    
    event BatchOperationCompleted(
        string operationType,
        uint256 successCount,
        uint256 failureCount,
        uint256 totalGasUsed
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the factory with security and gas optimization settings
     */
    function initialize(
        address admin_,
        address feeRecipient_,
        uint256 creationFee_,
        address tokenImplementation_
    ) external initializer {
        require(admin_ != address(0), "Factory: admin cannot be zero");
        require(feeRecipient_ != address(0), "Factory: fee recipient cannot be zero");
        require(tokenImplementation_ != address(0), "Factory: implementation cannot be zero");
        
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(FACTORY_ADMIN_ROLE, admin_);
        _grantRole(TOKEN_CREATOR_ROLE, admin_);
        _grantRole(UPGRADER_ROLE, admin_);
        
        feeRecipient = feeRecipient_;
        creationFee = creationFee_;
        tokenImplementation = tokenImplementation_;
        
        factoryStats.lastDeploymentTime = block.timestamp;
    }

    /**
     * @dev Creates a new token using CREATE2 for deterministic addresses
     * @param params Deployment parameters struct for gas optimization
     */
    function createToken(DeploymentParams calldata params) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
        onlyRole(TOKEN_CREATOR_ROLE) 
        returns (address) 
    {
        require(msg.value >= creationFee, "Factory: insufficient fee");
        require(bytes(params.name).length > 0, "Factory: name cannot be empty");
        require(bytes(params.symbol).length > 0, "Factory: symbol cannot be empty");
        require(params.decimals <= 18, "Factory: decimals too high");
        require(params.admin != address(0), "Factory: admin cannot be zero");
        
        uint256 gasStart = gasleft();
        
        // Generate deterministic address
        bytes32 salt = keccak256(abi.encodePacked(params.salt, msg.sender, block.timestamp));
        require(saltToAddress[salt] == address(0), "Factory: salt already used");
        
        // Deploy proxy with CREATE2
        address tokenAddress = _deployTokenProxy(params, salt);
        
        // Update factory statistics
        factoryStats.totalTokensCreated++;
        factoryStats.activeTokens++;
        factoryStats.lastDeploymentTime = block.timestamp;
        
        uint256 gasUsed = gasStart - gasleft();
        factoryStats.totalGasUsed += gasUsed;
        
        // Store token metadata
        deployedTokens[factoryStats.totalTokensCreated - 1] = tokenAddress;
        isFactoryToken[tokenAddress] = true;
        tokenCreationTime[tokenAddress] = block.timestamp;
        saltToAddress[salt] = tokenAddress;
        
        // Transfer creation fee
        if (msg.value > 0) {
            (bool success, ) = feeRecipient.call{value: msg.value}("");
            require(success, "Factory: fee transfer failed");
        }
        
        emit TokenCreated(
            tokenAddress,
            msg.sender,
            params.name,
            params.symbol,
            params.decimals,
            params.cap,
            params.initialSupply,
            params.salt,
            gasUsed,
            block.timestamp
        );
        
        return tokenAddress;
    }

    /**
     * @dev Internal function to deploy token proxy with CREATE2
     */
    function _deployTokenProxy(DeploymentParams calldata params, bytes32 salt) 
        internal 
        returns (address) 
    {
        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            SecureToken.initialize.selector,
            params.name,
            params.symbol,
            params.decimals,
            params.cap,
            params.admin,
            params.initialSupply
        );
        
        // Deploy proxy with CREATE2
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(tokenImplementation, initData)
        );
        
        address tokenAddress;
        assembly {
            tokenAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
            if iszero(extcodesize(tokenAddress)) {
                revert(0, 0)
            }
        }
        
        return tokenAddress;
    }

    /**
     * @dev Predicts token address before deployment
     * @param params Deployment parameters
     * @param salt_ Salt value for CREATE2
     */
    function predictTokenAddress(DeploymentParams calldata params, uint256 salt_) 
        external 
        view 
        returns (address predicted) 
    {
        bytes32 salt = keccak256(abi.encodePacked(salt_, msg.sender, block.timestamp));
        
        bytes memory initData = abi.encodeWithSelector(
            SecureToken.initialize.selector,
            params.name,
            params.symbol,
            params.decimals,
            params.cap,
            params.admin,
            params.initialSupply
        );
        
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(tokenImplementation, initData)
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(bytecode)
            )
        );
        
        return address(uint160(uint256(hash)));
    }

    /**
     * @dev Batch create multiple tokens for gas optimization
     * @param paramsArray Array of deployment parameters
     */
    function batchCreateTokens(DeploymentParams[] calldata paramsArray) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
        onlyRole(TOKEN_CREATOR_ROLE) 
        returns (address[] memory) 
    {
        require(paramsArray.length <= 20, "Factory: batch too large");
        require(msg.value >= creationFee * paramsArray.length, "Factory: insufficient batch fee");
        
        uint256 gasStart = gasleft();
        address[] memory newTokens = new address[](paramsArray.length);
        uint256 successCount = 0;
        uint256 failureCount = 0;
        
        for (uint256 i = 0; i < paramsArray.length;) {
            try this.createTokenInternal(paramsArray[i]) returns (address token) {
                newTokens[i] = token;
                successCount++;
            } catch {
                failureCount++;
            }
            unchecked { ++i; }
        }
        
        uint256 totalGasUsed = gasStart - gasleft();
        
        emit BatchOperationCompleted("CREATE_TOKENS", successCount, failureCount, totalGasUsed);
        
        return newTokens;
    }

    /**
     * @dev Internal function for batch token creation
     */
    function createTokenInternal(DeploymentParams calldata params) 
        external 
        returns (address) 
    {
        require(msg.sender == address(this), "Factory: internal function");
        
        bytes32 salt = keccak256(abi.encodePacked(params.salt, tx.origin, block.timestamp));
        return _deployTokenProxy(params, salt);
    }

    /**
     * @dev Batch burn tokens from multiple addresses (gas optimized)
     * @param tokenAddresses Array of token contract addresses
     * @param amounts Array of amounts to burn
     */
    function batchBurnTokens(
        address[] calldata tokenAddresses,
        uint256[] calldata amounts
    ) external nonReentrant whenNotPaused onlyRole(FACTORY_ADMIN_ROLE) {
        require(tokenAddresses.length == amounts.length, "Factory: arrays length mismatch");
        require(tokenAddresses.length <= 50, "Factory: batch too large");
        
        uint256 gasStart = gasleft();
        uint256 successCount = 0;
        uint256 failureCount = 0;
        
        for (uint256 i = 0; i < tokenAddresses.length;) {
            if (isFactoryToken[tokenAddresses[i]]) {
                try SecureToken(tokenAddresses[i]).burn(msg.sender, amounts[i]) {
                    emit TokenBurned(tokenAddresses[i], msg.sender, amounts[i], block.timestamp);
                    successCount++;
                } catch {
                    failureCount++;
                }
            } else {
                failureCount++;
            }
            unchecked { ++i; }
        }
        
        uint256 totalGasUsed = gasStart - gasleft();
        emit BatchOperationCompleted("BURN_TOKENS", successCount, failureCount, totalGasUsed);
    }

    /**
     * @dev Update creation fee
     * @param newFee New creation fee in wei
     */
    function updateCreationFee(uint256 newFee) external onlyRole(FACTORY_ADMIN_ROLE) {
        uint256 oldFee = creationFee;
        creationFee = newFee;
        emit FactoryFeeUpdated(oldFee, newFee);
    }

    /**
     * @dev Update fee recipient
     * @param newRecipient New fee recipient address
     */
    function updateFeeRecipient(address newRecipient) external onlyRole(FACTORY_ADMIN_ROLE) {
        require(newRecipient != address(0), "Factory: recipient cannot be zero");
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /**
     * @dev Update token implementation for future deployments
     * @param newImplementation New token implementation address
     */
    function updateTokenImplementation(address newImplementation) external onlyRole(FACTORY_ADMIN_ROLE) {
        require(newImplementation != address(0), "Factory: implementation cannot be zero");
        address oldImpl = tokenImplementation;
        tokenImplementation = newImplementation;
        emit TokenImplementationUpdated(oldImpl, newImplementation);
    }

    /**
     * @dev Get comprehensive factory statistics
     */
    function getFactoryStats() external view returns (
        uint256 totalTokensCreated,
        uint256 activeTokens,
        uint256 totalGasUsed,
        uint256 lastDeploymentTime,
        uint256 currentCreationFee,
        address currentFeeRecipient
    ) {
        return (
            factoryStats.totalTokensCreated,
            factoryStats.activeTokens,
            factoryStats.totalGasUsed,
            factoryStats.lastDeploymentTime,
            creationFee,
            feeRecipient
        );
    }

    /**
     * @dev Get deployed tokens in batches for gas efficiency
     * @param offset Starting index
     * @param limit Maximum number of tokens to return
     */
    function getDeployedTokensBatch(uint256 offset, uint256 limit) 
        external 
        view 
        returns (address[] memory tokens, uint256[] memory creationTimes) 
    {
        require(limit <= 100, "Factory: limit too high");
        
        uint256 totalTokens = factoryStats.totalTokensCreated;
        if (offset >= totalTokens) {
            return (new address[](0), new uint256[](0));
        }
        
        uint256 actualLimit = limit;
        if (offset + limit > totalTokens) {
            actualLimit = totalTokens - offset;
        }
        
        tokens = new address[](actualLimit);
        creationTimes = new uint256[](actualLimit);
        
        for (uint256 i = 0; i < actualLimit;) {
            address token = deployedTokens[offset + i];
            tokens[i] = token;
            creationTimes[i] = tokenCreationTime[token];
            unchecked { ++i; }
        }
    }

    /**
     * @dev Emergency pause functionality
     */
    function pause() external onlyRole(FACTORY_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause functionality
     */
    function unpause() external onlyRole(FACTORY_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Authorize contract upgrades
     */
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyRole(UPGRADER_ROLE) 
    {
        require(newImplementation != address(0), "Factory: invalid implementation");
    }

    /**
     * @dev Emergency function to recover accidentally sent ETH
     */
    function emergencyRecoverETH(address payable to, uint256 amount) 
        external 
        nonReentrant 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(to != address(0), "Factory: invalid recipient");
        require(amount <= address(this).balance, "Factory: insufficient balance");
        
        (bool success, ) = to.call{value: amount}("");
        require(success, "Factory: ETH recovery failed");
    }

    /**
     * @dev Emergency function to recover accidentally sent ERC20 tokens
     */
    function emergencyRecoverERC20(
        address token,
        address to,
        uint256 amount
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Factory: invalid recipient");
        
        IERC20(token).transfer(to, amount);
    }

    /**
     * @dev Receive function to accept ETH payments
     */
    receive() external payable {
        // Allow ETH deposits for fee payments
    }
}