// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title DePINRegistry
 * @notice A decentralized registry for DePIN (Decentralized Physical Infrastructure Network)
 *         devices on BOT Chain. Device operators register their hardware, submit data proofs,
 *         and earn BOT token rewards for verified contributions.
 * @dev Deployed on BOT Chain (Chain ID 677) — https://www.botchain.ai
 */
contract DePINRegistry is Ownable, ReentrancyGuard, Pausable {

    // ──────────────────────────────────────────────
    //  Enums & Structs
    // ──────────────────────────────────────────────

    enum DeviceStatus { Inactive, Active, Suspended }

    enum DeviceType { Sensor, Compute, Storage, Network, Other }

    struct Device {
        address owner;
        string  deviceId;       // off-chain unique identifier (e.g., serial number)
        string  metadata;       // JSON metadata (model, location, capabilities)
        DeviceType deviceType;
        DeviceStatus status;
        uint256 registeredAt;
        uint256 lastHeartbeat;  // last data submission timestamp
        uint256 totalSubmissions;
        uint256 totalRewardsEarned;
    }

    struct DataSubmission {
        uint256 deviceIndex;
        bytes32 dataHash;       // hash of the submitted data (proof of contribution)
        uint256 timestamp;
        uint256 reward;
    }

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    Device[] public devices;
    DataSubmission[] public submissions;

    mapping(string => uint256) public deviceIdToIndex;  // deviceId => array index + 1 (0 = not found)
    mapping(address => uint256[]) public ownerDevices;  // owner => device indices

    uint256 public registrationFee;        // BOT required to register a device
    uint256 public rewardPerSubmission;    // BOT reward per valid data submission
    uint256 public heartbeatInterval;      // max seconds between heartbeats before suspension
    uint256 public totalDevices;
    uint256 public totalActiveDevices;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event DeviceRegistered(uint256 indexed index, address indexed owner, string deviceId, DeviceType deviceType);
    event DeviceUpdated(uint256 indexed index, string metadata);
    event DeviceStatusChanged(uint256 indexed index, DeviceStatus newStatus);
    event DataSubmitted(uint256 indexed deviceIndex, bytes32 dataHash, uint256 reward);
    event RewardsClaimed(address indexed owner, uint256 amount);
    event RegistrationFeeUpdated(uint256 newFee);
    event RewardRateUpdated(uint256 newRate);

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    constructor(
        uint256 _registrationFee,
        uint256 _rewardPerSubmission,
        uint256 _heartbeatInterval
    ) Ownable() {
        registrationFee = _registrationFee;
        rewardPerSubmission = _rewardPerSubmission;
        heartbeatInterval = _heartbeatInterval;
    }

    // ──────────────────────────────────────────────
    //  Device Registration
    // ──────────────────────────────────────────────

    /// @notice Register a new DePIN device
    /// @param _deviceId Unique device identifier (serial number, etc.)
    /// @param _metadata JSON string with device info (model, location, specs)
    /// @param _deviceType Category of device
    function registerDevice(
        string calldata _deviceId,
        string calldata _metadata,
        DeviceType _deviceType
    ) external payable whenNotPaused {
        require(msg.value >= registrationFee, "Insufficient registration fee");
        require(bytes(_deviceId).length > 0, "Device ID required");
        require(deviceIdToIndex[_deviceId] == 0, "Device ID already registered");

        devices.push(Device({
            owner: msg.sender,
            deviceId: _deviceId,
            metadata: _metadata,
            deviceType: _deviceType,
            status: DeviceStatus.Active,
            registeredAt: block.timestamp,
            lastHeartbeat: block.timestamp,
            totalSubmissions: 0,
            totalRewardsEarned: 0
        }));

        uint256 index = devices.length; // 1-indexed for mapping
        deviceIdToIndex[_deviceId] = index;
        ownerDevices[msg.sender].push(index - 1); // 0-indexed for array access
        totalDevices++;
        totalActiveDevices++;

        emit DeviceRegistered(index - 1, msg.sender, _deviceId, _deviceType);
    }

    /// @notice Update device metadata (only by owner)
    function updateDevice(uint256 _index, string calldata _metadata) external {
        require(_index < devices.length, "Invalid index");
        require(devices[_index].owner == msg.sender, "Not device owner");
        devices[_index].metadata = _metadata;
        emit DeviceUpdated(_index, _metadata);
    }

    /// @notice Deactivate a device (owner or admin)
    function deactivateDevice(uint256 _index) external {
        require(_index < devices.length, "Invalid index");
        require(
            devices[_index].owner == msg.sender || msg.sender == owner(),
            "Not authorized"
        );
        require(devices[_index].status == DeviceStatus.Active, "Not active");

        devices[_index].status = DeviceStatus.Inactive;
        totalActiveDevices--;

        emit DeviceStatusChanged(_index, DeviceStatus.Inactive);
    }

    /// @notice Reactivate a device (only by owner)
    function reactivateDevice(uint256 _index) external {
        require(_index < devices.length, "Invalid index");
        require(devices[_index].owner == msg.sender, "Not device owner");
        require(devices[_index].status != DeviceStatus.Active, "Already active");

        devices[_index].status = DeviceStatus.Active;
        devices[_index].lastHeartbeat = block.timestamp;
        totalActiveDevices++;

        emit DeviceStatusChanged(_index, DeviceStatus.Active);
    }

    // ──────────────────────────────────────────────
    //  Data Submission & Rewards
    // ──────────────────────────────────────────────

    /// @notice Submit a data proof from a registered device and earn rewards
    /// @param _index Device index
    /// @param _dataHash Hash of the data being submitted (e.g., keccak256 of sensor reading)
    function submitData(uint256 _index, bytes32 _dataHash) external nonReentrant whenNotPaused {
        require(_index < devices.length, "Invalid index");
        Device storage device = devices[_index];
        require(device.owner == msg.sender, "Not device owner");
        require(device.status == DeviceStatus.Active, "Device not active");
        require(_dataHash != bytes32(0), "Invalid data hash");

        device.lastHeartbeat = block.timestamp;
        device.totalSubmissions++;

        uint256 reward = rewardPerSubmission;
        device.totalRewardsEarned += reward;

        submissions.push(DataSubmission({
            deviceIndex: _index,
            dataHash: _dataHash,
            timestamp: block.timestamp,
            reward: reward
        }));

        // Transfer reward to device owner
        if (reward > 0 && address(this).balance >= reward) {
            (bool ok, ) = msg.sender.call{value: reward}("");
            require(ok, "Reward transfer failed");
        }

        emit DataSubmitted(_index, _dataHash, reward);
    }

    // ──────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────

    /// @notice Get all device indices for an owner
    function getOwnerDevices(address _owner) external view returns (uint256[] memory) {
        return ownerDevices[_owner];
    }

    /// @notice Get device details by index
    function getDevice(uint256 _index) external view returns (
        address deviceOwner,
        string memory deviceId,
        string memory metadata,
        DeviceType deviceType,
        DeviceStatus status,
        uint256 registeredAt,
        uint256 lastHeartbeat,
        uint256 totalSubmissionsCount,
        uint256 totalRewardsEarnedAmount
    ) {
        require(_index < devices.length, "Invalid index");
        Device storage d = devices[_index];
        return (d.owner, d.deviceId, d.metadata, d.deviceType, d.status,
                d.registeredAt, d.lastHeartbeat, d.totalSubmissions, d.totalRewardsEarned);
    }

    /// @notice Get total number of registered devices
    function getDeviceCount() external view returns (uint256) {
        return devices.length;
    }

    /// @notice Get total number of data submissions
    function getSubmissionCount() external view returns (uint256) {
        return submissions.length;
    }

    /// @notice Check if a device needs a heartbeat (stale detection)
    function isDeviceStale(uint256 _index) external view returns (bool) {
        require(_index < devices.length, "Invalid index");
        Device storage d = devices[_index];
        if (d.status != DeviceStatus.Active) return false;
        return block.timestamp > d.lastHeartbeat + heartbeatInterval;
    }

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    /// @notice Fund the contract for device rewards
    function fundRewards() external payable onlyOwner {
        require(msg.value > 0, "No value");
    }

    /// @notice Suspend a device (admin only, e.g., for abuse)
    function suspendDevice(uint256 _index) external onlyOwner {
        require(_index < devices.length, "Invalid index");
        require(devices[_index].status == DeviceStatus.Active, "Not active");
        devices[_index].status = DeviceStatus.Suspended;
        totalActiveDevices--;
        emit DeviceStatusChanged(_index, DeviceStatus.Suspended);
    }

    function setRegistrationFee(uint256 _fee) external onlyOwner {
        registrationFee = _fee;
        emit RegistrationFeeUpdated(_fee);
    }

    function setRewardPerSubmission(uint256 _reward) external onlyOwner {
        rewardPerSubmission = _reward;
        emit RewardRateUpdated(_reward);
    }

    function setHeartbeatInterval(uint256 _interval) external onlyOwner {
        heartbeatInterval = _interval;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /// @notice Withdraw excess BOT (emergency)
    function emergencyWithdraw(uint256 _amount) external onlyOwner {
        (bool ok, ) = owner().call{value: _amount}("");
        require(ok, "Withdraw failed");
    }

    receive() external payable {}
}
