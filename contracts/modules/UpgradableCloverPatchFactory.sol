pragma solidity 0.5.8;

import "./CloverPatchFactory.sol";
import "../interfaces/ICloverPatchRegistry.sol";
import "../proxy/OwnedUpgradeabilityProxy.sol";


/**
 * @title Factory for deploying upgradable modules
 */
contract UpgradableCloverPatchFactory is CloverPatchFactory {

    event LogicContractSet(string _version, uint256 _upgrade, address _logicContract, bytes _upgradeData);

    event CloverPatchUpgraded(
        address indexed _cloverpatch,
        address indexed _cloverpatchToken,
        uint256 indexed _version
    );

    struct LogicContract {
        string version;
        address logicContract;
        bytes upgradeData;
    }

    // Mapping from version to logic contract
    mapping (uint256 => LogicContract) public logicContracts;

    // Mapping from Security Token address, to deployed proxy module address, to module version
    mapping (address => mapping (address => uint256)) public cloverpatch;

    // Mapping of which security token owns a given module
    mapping (address => address) public cloverpatchToCloverPatchToken;

    // Current version
    uint256 public latestUpgrade;

    /**
     * @notice Constructor
     * @param _setupCost Setup cost of the cloverpatch
      * @param _logicContract Contract address that contains the logic related to `description`
     * @param _cloverpatchmathRegistry Address of the CloverPatchmath registry
     * @param _isCostInClovers true = cost in Clovers, false = USD
     */
    constructor(
        string memory _version,
        uint256 _setupCost,
        address _logicContract,
        address _cloverpatchmathRegistry,
        bool _isCostInClovers
    )
        public CloverPatchFactory(_setupCost, _cloverpatchmathRegistry, _isCostInClovers)
    {
        require(_logicContract != address(0), "Invalid address");
        logicContracts[latestUpgrade].logicContract = _logicContract;
        logicContracts[latestUpgrade].version = _version;
    }

    /**
     * @notice Used to upgrade the module factory
     * @param _version Version of upgraded module
     * @param _logicContract Address of deployed module logic contract referenced from proxy
     * @param _upgradeData Data to be passed in call to upgradeToAndCall when a token upgrades its module
     */
    function setLogicContract(string calldata _version, address _logicContract, bytes calldata _upgradeData) external onlyOwner {
        require(keccak256(abi.encodePacked(_version)) != keccak256(abi.encodePacked(logicContracts[latestUpgrade].version)), "Same version");
        require(_logicContract != logicContracts[latestUpgrade].logicContract, "Same version");
        require(_logicContract != address(0), "Invalid address");
        latestUpgrade++;
        _modifyLogicContract(latestUpgrade, _version, _logicContract, _upgradeData);
    }

    /**
     * @notice Used to update an existing token logic contract
     * @param _upgrade logic contract to upgrade
     * @param _version Version of upgraded module
     * @param _logicContract Address of deployed module logic contract referenced from proxy
     * @param _upgradeData Data to be passed in call to upgradeToAndCall when a token upgrades its module
     */
    function updateLogicContract(uint256 _upgrade, string calldata _version, address _logicContract, bytes calldata _upgradeData) external onlyOwner {
        require(_upgrade <= latestUpgrade, "Invalid upgrade");
        // version & contract must differ from previous version, otherwise upgrade proxy will fail
        if (_upgrade > 0) {
          require(keccak256(abi.encodePacked(_version)) != keccak256(abi.encodePacked(logicContracts[_upgrade - 1].version)), "Same version");
          require(_logicContract != logicContracts[_upgrade - 1].logicContract, "Same version");
        }
        require(_logicContract != address(0), "Invalid address");
        require(_upgradeData.length > 4, "Invalid Upgrade");
        _modifyLogicContract(_upgrade, _version, _logicContract, _upgradeData);
    }

    function _modifyLogicContract(uint256 _upgrade, string memory _version, address _logicContract, bytes memory _upgradeData) internal {
        logicContracts[_upgrade].version = _version;
        logicContracts[_upgrade].logicContract = _logicContract;
        logicContracts[_upgrade].upgradeData = _upgradeData;
        ICloverPatchRegistry cloverpatchRegistry = ICloverPatchRegistry(cloverpatchRegistry.getAddress("CloverPatchRegistry"));
        cloverpatchRegistry.unverifyCloverPatchaddress(this));
        emit LogicContractSet(_version, _upgrade, _logicContract, _upgradeData);
    }

    /**
     * @notice Used by a security token to upgrade a given module
     * @param _module Address of (proxy) module to be upgraded
     */
    function upgrade(address _cloverpatch) external {
        // Only allow the owner of a module to upgrade it
        require(moduleToCloverPatchToken[_cloverpatch] == msg.sender, "Incorrect caller");
        // Only allow issuers to upgrade in single step verisons to preserve upgradeToAndCall semantics
        uint256 newVersion = modules[msg.sender][_cloverpatch] + 1;
        require(newVersion <= latestUpgrade, "Incorrect version");
        OwnedUpgradeabilityProxy(address(uint160(_cloverpatch))).upgradeToAndCall(logicContracts[newVersion].version, logicContracts[newVersion].logicContract, logicContracts[newVersion].upgradeData);
        modules[msg.sender][_cloverpatch] = newVersion;
        emit CloverPatchUpgraded(
            _cloverpatch,
            msg.sender,
            newVersion
        );
    }

    /**
     * @notice Used to initialize the module
     * @param _module Address of module
     * @param _data Data used for the intialization of the module factory variables
     */
    function _initializeCloverPatch(address _cloverpatch, bytes memory _data) internal {
        super._initializeCloverPatch(_cloverpatch, _data);
        moduleToCloverPatchToken[_cloverpatch] = msg.sender;
        modules[msg.sender][_cloverpatch] = latestUpgrade;
    }

    /**
     * @notice Get the version related to the cloverpatch factory
     */
    function version() external view returns(string memory) {
        return logicContracts[latestUpgrade].version;
    }

}
