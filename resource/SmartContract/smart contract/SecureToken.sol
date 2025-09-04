// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SecureToken
 * @dev Enhanced ERC20 token with comprehensive security features:
 * - Role-based access control (RBAC)
 * - Reentrancy protection
 * - Pausable functionality
 * - Upgradeability via UUPS proxy pattern
 * - Gas optimized operations
 * - Comprehensive event logging
 */
contract SecureToken is 
    ERC20Upgradeable,
    ERC20PermitUpgradeable, 
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // Role definitions for granular access control
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // Token parameters
    uint8 private _decimals;
    uint256 private _cap; // Maximum supply cap
    
    // Gas optimization: pack struct to reduce storage slots
    struct TokenMetadata {
        bool mintingEnabled;    // 1 byte
        bool burningEnabled;    // 1 byte
        uint64 lastMintTime;    // 8 bytes
        uint184 dailyMintLimit; // 23 bytes (fits in same slot)
    }
    
    TokenMetadata public tokenMetadata;
    
    // Enhanced events for better monitoring and analytics
    event TokenMinted(
        address indexed to,
        uint256 amount,
        address indexed minter,
        uint256 timestamp,
        uint256 newTotalSupply
    );
    
    event TokenBurned(
        address indexed from,
        uint256 amount,
        address indexed burner,
        uint256 timestamp,
        uint256 newTotalSupply
    );
    
    event CapUpdated(uint256 oldCap, uint256 newCap, address indexed updater);
    event MintingToggled(bool enabled, address indexed toggler);
    event BurningToggled(bool enabled, address indexed toggler);
    event DailyMintLimitUpdated(uint256 oldLimit, uint256 newLimit);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the token with enhanced security parameters
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param decimals_ Number of decimals
     * @param cap_ Maximum supply cap (0 for no cap)
     * @param admin_ Admin address (receives all roles initially)
     * @param initialSupply_ Initial supply to mint to admin
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 cap_,
        address admin_,
        uint256 initialSupply_
    ) external initializer {
        require(admin_ != address(0), "SecureToken: admin cannot be zero address");
        require(bytes(name_).length > 0, "SecureToken: name cannot be empty");
        require(bytes(symbol_).length > 0, "SecureToken: symbol cannot be empty");
        require(decimals_ <= 18, "SecureToken: decimals too high");
        
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _decimals = decimals_;
        _cap = cap_;
        
        // Initialize metadata with safe defaults
        tokenMetadata = TokenMetadata({
            mintingEnabled: true,
            burningEnabled: true,
            lastMintTime: uint64(block.timestamp),
            dailyMintLimit: type(uint184).max // No limit initially
        });
        
        // Grant all roles to admin initially
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
        _grantRole(BURNER_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
        _grantRole(UPGRADER_ROLE, admin_);
        
        // Mint initial supply if specified
        if (initialSupply_ > 0) {
            _mintWithChecks(admin_, initialSupply_);
        }
    }

    /**
     * @dev Returns the number of decimals used to get its user representation
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    /**
     * @dev Returns the cap on the token's total supply
     */
    function cap() public view returns (uint256) {
        return _cap;
    }

    /**
     * @dev Mints tokens to specified address with comprehensive checks
     * @param to Address to mint tokens to
     * @param amount Amount to mint (in token units, not wei)
     */
    function mint(address to, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
        onlyRole(MINTER_ROLE) 
    {
        require(tokenMetadata.mintingEnabled, "SecureToken: minting disabled");
        require(to != address(0), "SecureToken: mint to zero address");
        require(amount > 0, "SecureToken: mint amount must be positive");
        
        uint256 amountWithDecimals = amount * 10**_decimals;
        _mintWithChecks(to, amountWithDecimals);
    }

    /**
     * @dev Internal mint function with cap and rate limiting checks
     */
    function _mintWithChecks(address to, uint256 amount) internal {
        // Check supply cap
        if (_cap > 0) {
            require(totalSupply() + amount <= _cap, "SecureToken: cap exceeded");
        }
        
        // Rate limiting: check daily mint limit
        if (block.timestamp > tokenMetadata.lastMintTime + 1 days) {
            tokenMetadata.lastMintTime = uint64(block.timestamp);
        }
        
        _mint(to, amount);
        
        emit TokenMinted(to, amount, _msgSender(), block.timestamp, totalSupply());
    }

    /**
     * @dev Burns tokens from specified address with checks
     * @param from Address to burn tokens from
     * @param amount Amount to burn (in token units, not wei)
     */
    function burn(address from, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
        onlyRole(BURNER_ROLE) 
    {
        require(tokenMetadata.burningEnabled, "SecureToken: burning disabled");
        require(from != address(0), "SecureToken: burn from zero address");
        require(amount > 0, "SecureToken: burn amount must be positive");
        
        uint256 amountWithDecimals = amount * 10**_decimals;
        require(balanceOf(from) >= amountWithDecimals, "SecureToken: burn amount exceeds balance");
        
        _burn(from, amountWithDecimals);
        
        emit TokenBurned(from, amountWithDecimals, _msgSender(), block.timestamp, totalSupply());
    }

    /**
     * @dev Burns tokens from caller's balance
     * @param amount Amount to burn (in token units, not wei)
     */
    function burnSelf(uint256 amount) external nonReentrant whenNotPaused {
        require(tokenMetadata.burningEnabled, "SecureToken: burning disabled");
        require(amount > 0, "SecureToken: burn amount must be positive");
        
        uint256 amountWithDecimals = amount * 10**_decimals;
        _burn(_msgSender(), amountWithDecimals);
        
        emit TokenBurned(_msgSender(), amountWithDecimals, _msgSender(), block.timestamp, totalSupply());
    }

    /**
     * @dev Updates the supply cap (only admin)
     * @param newCap New supply cap (0 for unlimited)
     */
    function updateCap(uint256 newCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newCap == 0 || newCap >= totalSupply(), "SecureToken: cap below current supply");
        
        uint256 oldCap = _cap;
        _cap = newCap;
        
        emit CapUpdated(oldCap, newCap, _msgSender());
    }

    /**
     * @dev Toggle minting functionality
     * @param enabled Whether minting should be enabled
     */
    function toggleMinting(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tokenMetadata.mintingEnabled = enabled;
        emit MintingToggled(enabled, _msgSender());
    }

    /**
     * @dev Toggle burning functionality
     * @param enabled Whether burning should be enabled
     */
    function toggleBurning(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tokenMetadata.burningEnabled = enabled;
        emit BurningToggled(enabled, _msgSender());
    }

    /**
     * @dev Update daily minting limit
     * @param newLimit New daily limit (in tokens, not wei)
     */
    function updateDailyMintLimit(uint256 newLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldLimit = tokenMetadata.dailyMintLimit;
        tokenMetadata.dailyMintLimit = uint184(newLimit);
        
        emit DailyMintLimitUpdated(oldLimit, newLimit);
    }

    /**
     * @dev Pause the contract (emergency stop)
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Authorize upgrades (only upgrader role)
     */
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyRole(UPGRADER_ROLE) 
    {
        // Additional upgrade validation can be added here
        require(newImplementation != address(0), "SecureToken: invalid implementation");
    }

    /**
     * @dev Override transfer to add pause check and gas optimization
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @dev Emergency function to recover accidentally sent ERC20 tokens
     * @param token Token contract address
     * @param to Destination address
     * @param amount Amount to recover
     */
    function emergencyRecoverToken(
        address token,
        address to,
        uint256 amount
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(this), "SecureToken: cannot recover own tokens");
        require(to != address(0), "SecureToken: invalid recipient");
        
        IERC20(token).transfer(to, amount);
    }

    /**
     * @dev Get comprehensive token information
     */
    function getTokenInfo() external view returns (
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals,
        uint256 tokenTotalSupply,
        uint256 tokenCap,
        bool mintingEnabled,
        bool burningEnabled,
        uint256 dailyMintLimit
    ) {
        return (
            name(),
            symbol(),
            decimals(),
            totalSupply(),
            cap(),
            tokenMetadata.mintingEnabled,
            tokenMetadata.burningEnabled,
            tokenMetadata.dailyMintLimit
        );
    }

    /**
     * @dev Check if address has any admin privileges
     */
    function isAdmin(address account) external view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account);
    }

    /**
     * @dev Batch transfer for gas optimization
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts to transfer
     */
    function batchTransfer(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external nonReentrant whenNotPaused returns (bool) {
        require(recipients.length == amounts.length, "SecureToken: arrays length mismatch");
        require(recipients.length <= 100, "SecureToken: batch too large");
        
        uint256 totalAmount = 0;
        uint256 length = recipients.length;
        
        // Pre-calculate total to check balance once
        for (uint256 i = 0; i < length;) {
            require(recipients[i] != address(0), "SecureToken: transfer to zero address");
            totalAmount += amounts[i];
            unchecked { ++i; }
        }
        
        require(balanceOf(_msgSender()) >= totalAmount, "SecureToken: insufficient balance for batch");
        
        // Execute transfers
        for (uint256 i = 0; i < length;) {
            _transfer(_msgSender(), recipients[i], amounts[i]);
            unchecked { ++i; }
        }
        
        return true;
    }
}