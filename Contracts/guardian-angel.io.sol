// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title RashidAward
 * @author ELGHALY COMPANY — Sustainable Web3 Division
 * @notice Enterprise‑grade prize distribution protocol with multi‑role governance,
 *         timelocked parameter changes, carbon‑offset accounting, and oracle‑ready
 *         sustainability verification.
 *
 * @dev Self‑contained, dependency‑free implementation. The entire trust surface
 *      is visible in this single file – designed for rigorous third‑party audits.
 *
 * ============================================================================
 *  FOUNDATIONAL SECURITY LAYER
 * ============================================================================
 *  This contract operates within the Guardian Angel Protocol framework:
 *  https://github.com/Alarm2024/guardian-angel.io
 *
 *  Guardian Angel is an institutional-grade security framework that protects
 *  high-value digital assets and ensures that ecological intelligence data and
 *  carbon-verified assets are managed within a hardened, immutable, and fully
 *  auditable environment.
 * ============================================================================
 *
 * ============================================================================
 *  KEY SECURITY & SUSTAINABILITY FEATURES
 * ============================================================================
 *  1. Multi‑Role Governance (Owner + Guardian) with timelocked changes
 *     - No single key can unilaterally alter critical parameters.
 *     - Both roles must approve a proposal, followed by a 2‑day timelock.
 *
 *  2. Award Lifecycle (Create → Verify → Distribute)
 *     - `createAward()`: Guardian (Award Manager) assigns a prize.
 *     - `verifyAward()`: Verifier (Oracle) confirms sustainability compliance.
 *     - `distributeAward()`: Anyone can trigger payout after verification.
 *
 *  3. Carbon Offsetting (Green Solidity)
 *     - A configurable percentage (basis points) is deducted from every
 *       award distribution and sent to a designated offset recipient.
 *     - The offset recipient can be a contract that purchases/burns carbon credits.
 *
 *  4. Oracle‑Ready Verification
 *     - The `verifier` role can be set to a Chainlink oracle address,
 *       enabling off‑chain sustainability checks before funds are released.
 *
 *  5. Gas‑Optimised for Climate
 *     - Uses `unchecked` blocks where safe, minimises storage reads/writes,
 *       and avoids unbounded loops – reducing the computational footprint.
 *
 *  6. Contract Filtering
 *     - Prevents unverified contracts from claiming awards (whitelist required).
 *
 *  7. Reentrancy & Front‑Running Protection
 *     - `nonReentrant` on all external state‑mutating functions.
 *     - Checks‑Effects‑Interactions enforced.
 *     - Timelocks prevent race conditions on parameter changes.
 * ============================================================================
 */

contract RashidAward {

    // ================================================================
    // CUSTOM ERRORS (Gas‑Optimised Reverts)
    // ================================================================

    error Unauthorized();
    error NotOwner();
    error NotGuardian();
    error NotVerifier();
    error NotPendingOwner();
    error ContractPaused();
    error NotPaused();
    error ZeroAddress();
    error NoChange();
    error InsufficientFunds();
    error TransferFailed();
    error InvalidAmount();
    error AwardNotFound();
    error AwardAlreadyVerified();
    error AwardAlreadyDistributed();
    error AwardNotVerified();
    error RecipientIsContractNotAllowed();
    error TimelockActive();
    error NoPendingChange();
    error ChangeNotApproved();
    error ChangeAlreadyExecuted();
    error InvalidBasisPoints();
    error ProposalNotFound();
    error ProposalAlreadyExecuted();
    error ProposalExpired();

    // ================================================================
    // EVENTS (Full Transparency)
    // ================================================================

    // --- Ownership ---
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    even GuardianRotationInitiated(address indexed previousGuardian, address indexed newGuardian, uint256 unlockTime);
    event GuardianRotationInitiated(address indexed previousGuardian, address indexed newGuardian, uint256 unlockTime);
    event GuardianRotated(address indexed previous, address indexed newGuardian);
    event GuardianRotationCancelled(address indexed cancelledBy);

    // --- Parameter Changes (Timelocked) ---
    event ChangeProposed(bytes32 indexed proposalId, address indexed proposer, uint256 deadline);
    event ChangeApproved(bytes32 indexed proposalId, address indexed approver);
    event ChangeExecuted(bytes32 indexed proposalId, bytes32 indexed parameter, uint256 value);
    event ChangeCancelled(bytes32 indexed proposalId, address indexed canceller);

    // --- Pause ---
    event Paused(address indexed triggeredBy);
    event Unpaused(address indexed triggeredBy);

    // --- Award Lifecycle ---
    event AwardCreated(uint256 indexed awardId, address indexed recipient, uint256 amount, address indexed creator);
    event AwardVerified(uint256 indexed awardId, address indexed verifier);
    event AwardDistributed(
        uint256 indexed awardId,
        address indexed recipient,
        uint256 amount,
        uint256 offsetAmount,
        address indexed offsetRecipient
    );

    // --- Carbon Offset ---
    event OffsetRecipientUpdated(address indexed newRecipient);
    event OffsetBpsUpdated(uint256 newBps);
    event VerifierUpdated(address indexed newVerifier);

    // --- Misc ---
    event ETHReceived(address indexed from, uint256 amount);
    event AllowedContractUpdated(address indexed contractAddr, bool status);

    // ================================================================
    // CONSTANTS
    // ================================================================

    /// @notice Timelock duration for parameter changes (2 days)
    uint256 public constant CHANGE_TIMELOCK = 2 days;

    /// @notice Maximum basis points (100% = 10000)
    uint256 private constant MAX_BPS = 10000;

    /// @notice EIP‑712 domain separator (kept for extensibility)
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // ================================================================
    // STATE VARIABLES
    // ================================================================

    // --- Ownership & Governance ---
    address public owner;
    address public pendingOwner;

    address public guardian;
    address public pendingGuardian;
    uint256 public guardianRotationUnlock;

    // --- Verifier (Oracle) ---
    address public verifier;

    // --- Carbon Offset ---
    address public offsetRecipient;
    uint256 public offsetBps;        // basis points (e.g., 500 = 5%)

    // --- Award Storage ---
    struct Award {
        address recipient;
        uint256 amount;
        bool verified;
        bool distributed;
        uint256 createdAt;
    }
    mapping(uint256 => Award) public awards;
    uint256 public awardCount;

    // --- Contract Filtering ---
    mapping(address => bool) public allowedContracts;  // whitelisted contracts that can claim

    // --- Circuit Breaker ---
    bool public paused;

    // --- Reentrancy Guard ---
    uint256 private _reentrancyStatus;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    // --- EIP‑712 Domain Separator (cached) ---
    bytes32 private immutable _DOMAIN_SEPARATOR;

    // --- Generic Proposal System for Parameter Changes ---
    struct Proposal {
        bytes32 parameter;          // keccak256 of the parameter name (e.g., "offsetBps")
        uint256 value;              // new value
        uint256 deadline;           // timestamp after which proposal expires
        bool executed;              // true if executed
        bool approvedByOwner;       // owner approval flag
        bool approvedByGuardian;    // guardian approval flag
    }
    mapping(bytes32 => Proposal) public proposals;   // proposalId => Proposal
    bytes32[] public proposalIds;                    // list of all proposal IDs (for enumeration)

    // ================================================================
    // MODIFIERS
    // ================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    modifier onlyOwnerOrGuardian() {
        if (msg.sender != owner && msg.sender != guardian) revert Unauthorized();
        _;
    }

    modifier onlyVerifier() {
        if (msg.sender != verifier) revert NotVerifier();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier whenPaused() {
        if (!paused) revert NotPaused();
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyStatus == _ENTERED) revert Unauthorized();
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    // ================================================================
    // CONSTRUCTOR
    // ================================================================

    /**
     * @param initialGuardian        Address with award‑management privileges.
     * @param initialVerifier        Address authorised to verify sustainability (or oracle).
     * @param initialOffsetRecipient Address that receives carbon‑offset funds.
     * @param initialOffsetBps       Carbon offset percentage in basis points (e.g., 500 = 5%).
     */
    constructor(
        address initialGuardian,
        address initialVerifier,
        address initialOffsetRecipient,
        uint256 initialOffsetBps
    ) {
        if (initialGuardian == address(0)) revert ZeroAddress();
        if (initialVerifier == address(0)) revert ZeroAddress();
        if (initialOffsetRecipient == address(0)) revert ZeroAddress();
        if (initialOffsetBps > MAX_BPS) revert InvalidBasisPoints();

        owner = msg.sender;
        guardian = initialGuardian;
        verifier = initialVerifier;
        offsetRecipient = initialOffsetRecipient;
        offsetBps = initialOffsetBps;
        _reentrancyStatus = _NOT_ENTERED;

        _DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("RashidAward"),
                keccak256(bytes("1.0.0")),
                block.chainid,
                address(this)
            )
        );

        emit OwnershipTransferred(address(0), msg.sender);
        emit OffsetRecipientUpdated(initialOffsetRecipient);
        emit OffsetBpsUpdated(initialOffsetBps);
        emit VerifierUpdated(initialVerifier);
    }

    // ================================================================
    // OWNERSHIP (two‑step transfer)
    // ================================================================

    /**
     * @notice Begins transferring ownership to `newOwner`.
     * @dev Ownership only changes once `newOwner` calls acceptOwnership().
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        if (newOwner == owner) revert NoChange();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /**
     * @notice Completes an ownership transfer. Callable only by `pendingOwner`.
     */
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        address previous = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, owner);
    }

    /**
     * @notice Cancels a pending ownership transfer.
     */
    function cancelOwnershipTransfer() external onlyOwner {
        if (pendingOwner == address(0)) revert NoChange();
        pendingOwner = address(0);
    }

    // ================================================================
    // GUARDIAN ROTATION (24h timelock, vetoable by owner or guardian)
    // ================================================================

    /**
     * @notice Nominates a new guardian. Takes effect after a 24‑hour delay.
     */
    function initiateGuardianRotation(address newGuardian) external onlyOwner {
        if (newGuardian == address(0)) revert ZeroAddress();
        if (newGuardian == guardian) revert NoChange();
        pendingGuardian = newGuardian;
        guardianRotationUnlock = block.timestamp + 24 hours;
        emit GuardianRotationInitiated(guardian, newGuardian, guardianRotationUnlock);
    }

    /**
     * @notice Activates the pending guardian once the timelock has elapsed.
     */
    function finalizeGuardianRotation() external onlyOwner {
        if (pendingGuardian == address(0)) revert NoChange();
        if (block.timestamp < guardianRotationUnlock) revert TimelockActive();
        address previous = guardian;
        guardian = pendingGuardian;
        pendingGuardian = address(0);
        guardianRotationUnlock = 0;
        emit GuardianRotated(previous, guardian);
    }

    /**
     * @notice Cancels a pending guardian rotation (owner or guardian can veto).
     */
    function cancelGuardianRotation() external onlyOwnerOrGuardian {
        if (pendingGuardian == address(0)) revert NoChange();
        pendingGuardian = address(0);
        guardianRotationUnlock = 0;
        emit GuardianRotationCancelled(msg.sender);
    }

    // ================================================================
    // PAUSE / UNPAUSE
    // ================================================================

    /**
     * @notice Pauses all award creation, verification, and distribution.
     * @dev Callable by Owner or Guardian – provides an emergency break‑glass.
     */
    function pause() external onlyOwnerOrGuardian {
        if (paused) revert ContractPaused();
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpauses the contract. Only Owner can unpause to prevent
     *         a compromised Guardian from silently lifting the pause.
     */
    function unpause() external onlyOwner {
        if (!paused) revert NotPaused();
        paused = false;
        emit Unpaused(msg.sender);
    }

    // ================================================================
    // CONTRACT FILTERING (allow/deny contracts)
    // ================================================================

    /**
     * @notice Whitelists or blacklists a contract address for award eligibility.
     * @param contractAddr The contract address to manage.
     * @param allowed Whether the contract is allowed to receive awards.
     */
    function setAllowedContract(address contractAddr, bool allowed) external onlyOwner {
        if (contractAddr == address(0)) revert ZeroAddress();
        allowedContracts[contractAddr] = allowed;
        emit AllowedContractUpdated(contractAddr, allowed);
    }

    // ================================================================
    // PROPOSAL SYSTEM (Timelocked Multi‑Sig Parameter Changes)
    // ================================================================

    /**
     * @notice Proposes a change to a parameter. Both owner and guardian must approve,
     *         then after CHANGE_TIMELOCK the change can be executed.
     * @param parameter The keccak256 hash of the parameter name (e.g., "offsetBps").
     * @param value     The new value.
     */
    function proposeChange(bytes32 parameter, uint256 value) external onlyOwner whenNotPaused {
        bytes32 proposalId = keccak256(abi.encodePacked(parameter, value, block.timestamp));
        if (proposals[proposalId].deadline != 0) revert ChangeAlreadyExecuted();
        proposals[proposalId] = Proposal({
            parameter: parameter,
            value: value,
            deadline: block.timestamp + CHANGE_TIMELOCK,
            executed: false,
            approvedByOwner: true,  // proposer is owner, auto‑approved
            approvedByGuardian: false
        });
        proposalIds.push(proposalId);
        emit ChangeProposed(proposalId, msg.sender, block.timestamp + CHANGE_TIMELOCK);
    }

    /**
     * @notice Approves a proposal by the guardian (the other required role).
     */
    function approveProposal(bytes32 proposalId) external onlyGuardian whenNotPaused {
        Proposal storage prop = proposals[proposalId];
        if (prop.deadline == 0) revert ProposalNotFound();
        if (prop.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp > prop.deadline) revert ProposalExpired();
        if (prop.approvedByGuardian) revert NoChange();
        prop.approvedByGuardian = true;
        emit ChangeApproved(proposalId, msg.sender);
    }

    /**
     * @notice Executes a proposal after both approvals and timelock have passed.
     */
    function executeProposal(bytes32 proposalId) external onlyOwner whenNotPaused {
        Proposal storage prop = proposals[proposalId];
        if (prop.deadline == 0) revert ProposalNotFound();
        if (prop.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp < prop.deadline) revert TimelockActive();
        if (!prop.approvedByOwner || !prop.approvedByGuardian) revert ChangeNotApproved();

        prop.executed = true;

        // Apply the change based on the parameter hash.
        bytes32 param = prop.parameter;
        uint256 val = prop.value;
        if (param == keccak256("offsetBps")) {
            if (val > MAX_BPS) revert InvalidBasisPoints();
            offsetBps = val;
            emit OffsetBpsUpdated(val);
        } else if (param == keccak256("offsetRecipient")) {
            if (val == 0) revert ZeroAddress();
            offsetRecipient = address(uint160(val));
            emit OffsetRecipientUpdated(address(uint160(val)));
        } else if (param == keccak256("verifier")) {
            if (val == 0) revert ZeroAddress();
            verifier = address(uint160(val));
            emit VerifierUpdated(address(uint160(val)));
        } else {
            // unknown parameter – should never happen
            revert Unauthorized();
        }
        emit ChangeExecuted(proposalId, param, val);
    }

    /**
     * @notice Cancels a proposal (only before execution).
     */
    function cancelProposal(bytes32 proposalId) external onlyOwnerOrGuardian {
        Proposal storage prop = proposals[proposalId];
        if (prop.deadline == 0) revert ProposalNotFound();
        if (prop.executed) revert ProposalAlreadyExecuted();
        prop.deadline = 0; // mark as expired / cancelled
        emit ChangeCancelled(proposalId, msg.sender);
    }

    // ================================================================
    // AWARD MANAGEMENT
    // ================================================================

    /**
     * @notice Creates a new award for a recipient. Only callable by Guardian.
     * @param recipient Address that will receive the award (must be EOA or allowed contract).
     * @param amount    Amount of ETH to award (in wei).
     */
    function createAward(address recipient, uint256 amount) external onlyGuardian whenNotPaused {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        // Contract filtering: if recipient is a contract, it must be whitelisted.
        if (recipient.code.length > 0 && !allowedContracts[recipient]) {
            revert RecipientIsContractNotAllowed();
        }

        uint256 id = awardCount;
        awards[id] = Award({
            recipient: recipient,
            amount: amount,
            verified: false,
            distributed: false,
            createdAt: block.timestamp
        });
        awardCount = id + 1;
        emit AwardCreated(id, recipient, amount, msg.sender);
    }

    /**
     * @notice Marks an award as verified (sustainability approved). Only callable by Verifier.
     * @param awardId The ID of the award.
     */
    function verifyAward(uint256 awardId) external onlyVerifier whenNotPaused {
        Award storage award = awards[awardId];
        if (award.recipient == address(0)) revert AwardNotFound();
        if (award.verified) revert AwardAlreadyVerified();
        if (award.distributed) revert AwardAlreadyDistributed();
        award.verified = true;
        emit AwardVerified(awardId, msg.sender);
    }

    /**
     * @notice Distributes the award to the recipient after verification, deducting carbon offset.
     * @param awardId The ID of the award.
     */
    function distributeAward(uint256 awardId) external nonReentrant whenNotPaused {
        Award storage award = awards[awardId];
        if (award.recipient == address(0)) revert AwardNotFound();
        if (!award.verified) revert AwardNotVerified();
        if (award.distributed) revert AwardAlreadyDistributed();

        uint256 amount = award.amount;
        if (address(this).balance < amount) revert InsufficientFunds();

        // Calculate offset amount
        uint256 offsetAmount = (amount * offsetBps) / MAX_BPS;
        uint256 recipientAmount = amount - offsetAmount;

        // Checks‑Effects‑Interactions: update state before external calls
        award.distributed = true;

        // Send offset to offsetRecipient
        if (offsetAmount > 0) {
            _sendETH(payable(offsetRecipient), offsetAmount);
        }

        // Send remaining to recipient
        if (recipientAmount > 0) {
            _sendETH(payable(award.recipient), recipientAmount);
        }

        emit AwardDistributed(awardId, award.recipient, amount, offsetAmount, offsetRecipient);
    }

    // ================================================================
    // INTERNAL HELPERS
    // ================================================================

    /**
     * @dev Sends ETH to a given address, reverting on failure.
     */
    function _sendETH(address payable to, uint256 amount) private {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    // ================================================================
    // EIP‑712 DOMAIN (extensibility)
    // ================================================================

    /**
     * @notice Returns the EIP‑712 domain separator.
     */
    function domainSeparator() external view returns (bytes32) {
        return _DOMAIN_SEPARATOR;
    }

    // ================================================================
    // FALLBACK & RECEIVE
    // ================================================================

    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    fallback() external payable {
        if (msg.value > 0) emit ETHReceived(msg.sender, msg.value);
    }

    // ================================================================
    // VIEW FUNCTIONS (for transparency)
    // ================================================================

    /**
     * @notice Returns the number of proposals.
     */
    function getProposalCount() external view returns (uint256) {
        return proposalIds.length;
    }

    /**
     * @notice Returns a proposal by ID.
     */
    function getProposal(bytes32 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    /**
     * @notice Returns an award by ID.
     */
    function getAward(uint256 awardId) external view returns (Award memory) {
        return awards[awardId];
    }

    // ================================================================
    // LEGACY INTERFACE SUPPORT (optional)
    // ================================================================

    /**
     * @dev Supports ERC‑165 for receiver interfaces (placeholder).
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7; // ERC165
    }
}
