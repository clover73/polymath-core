pragma solidity 0.5.8;

import "../libraries/VersionUtils.sol";
import "../libraries/Util.sol";
import "../interfaces/ICloverPatch.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IPolymathRegistry.sol";
import "../interfaces/IModuleFactory.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../libraries/DecimalMath.sol";

/**
 * @title Interface that any module factory contract should implement
 * @notice Contract is abstract
 */
contract CloverPatchFactory is ICloverPatchFactoryFactory, Ownable {

    ICloverPatchRegistry public CloverPatchRegistry;

    string initialVersion;
    bytes32 public name;
    string public title;
    string public description;

    uint8[] typesData;
    bytes32[] tagsData;

    bool public isCostInClovers;
    uint256 public setupCost;

    string constant CLOVERPATCH_ORACLE = "StableCLOVERPATCHUsdOracle";

    // @notice Allow only two variables to be stored
    // 1. lowerBound
    // 2. upperBound
    // @dev (0.0.0 will act as the wildcard)
    // @dev uint24 consists packed value of uint8 _major, uint8 _minor, uint8 _patch
    mapping(string => uint24) compatibleSTVersionRange;

    /**
     * @notice Constructor
     */
    constructor(uint256 _setupCost, address _cloverpatchmathRegistry, bool _isCostInClovers) public {
        setupCost = _setupCost;
        cloverpatchmathRegistry = ICloverPatchmathRegistry(_cloverpatchmathRegistry);
        isCostInClovers = _isCostInClovers;
    }

    /**
     * @notice Type of the Gold factory
     */
    function getTypes() external view returns(uint8[] memory) {
        return typesData;
    }

    /**
     * @notice Get the tags related to the module factory
     */
    function getTags() external view returns(bytes32[] memory) {
        return tagsData;
    }

    /**
     * @notice Get the version related to the gold factory
     */
    function version() external view returns(string memory) {
        return initialVersion;
    }

    /**
     * @notice Used to change the fee of the setup cost
     * @param _setupCost new setup cost
     */
    function changeSetupCost(uint256 _setupCost) public onlyOwner {
        emit ChangeSetupCost(setupCost, _setupCost);
        setupCost = _setupCost;
    }

    /**
     * @notice Used to change the currency and amount of setup cost
     * @param _setupCost new setup cost
     * @param _isCostInClovers new setup cost currency. USD or CLOVERS
     */
    function changeCostAndType(uint256 _setupCost, bool _isCostInClovers) public onlyOwner {
        emit ChangeSetupCost(setupCost, _setupCost);
        emit ChangeCostType(isCostInClovers, _isCostInClovers);
        setupCost = _setupCost;
        isCostInClovers = _isCostInClovers;
    }

    /**
     * @notice Updates the title of the CloverPatchFactory
     * @param _title New Title that will replace the old one.
     */
    function changeTitle(string memory _title) public onlyOwner {
        require(bytes(_title).length > 0, "Invalid text");
        title = _title;
    }

    /**
     * @notice Updates the description of the CloverPatchFactory
     * @param _description New description that will replace the old one.
     */
    function changeDescription(string memory _description) public onlyOwner {
        require(bytes(_description).length > 0, "Invalid text");
        description = _description;
    }

    /**
     * @notice Updates the name of the CloverPatchFactory
     * @param _name New name that will replace the old one.
     */
    function changeName(bytes32 _name) public onlyOwner {
        require(_name != bytes32(0), "Invalid text");
        name = _name;
    }

    /**
     * @notice Updates the tags of the CloverPatchFactory
     * @param _tagsData New list of tags
     */
    function changeTags(bytes32[] memory _tagsData) public onlyOwner {
        require(_tagsData.length > 0, "Invalid text");
        tagsData = _tagsData;
    }

    /**
     * @notice Function use to change the lower and upper bound of the compatible version st
     * @param _boundType Type of bound
     * @param _newVersion new version array
     */
    function changeSTVersionBounds(string calldata _boundType, uint8[] calldata _newVersion) external onlyOwner {
        require(
            keccak256(abi.encodePacked(_boundType)) == keccak256(abi.encodePacked("lowerBound")) || keccak256(
                abi.encodePacked(_boundType)
            ) == keccak256(abi.encodePacked("upperBound")),
            "Invalid bound type"
        );
        require(_newVersion.length == 3, "Invalid version");
        if (compatibleSTVersionRange[_boundType] != uint24(0)) {
            uint8[] memory _currentVersion = VersionUtils.unpack(compatibleSTVersionRange[_boundType]);
            if (keccak256(abi.encodePacked(_boundType)) == keccak256(abi.encodePacked("lowerBound"))) {
                require(VersionUtils.lessThanOrEqual(_newVersion, _currentVersion), "Invalid version");
            } else {
                require(VersionUtils.greaterThanOrEqual(_newVersion, _currentVersion), "Invalid version");
            }
        }
        compatibleSTVersionRange[_boundType] = VersionUtils.pack(_newVersion[0], _newVersion[1], _newVersion[2]);
        emit ChangeSTVersionBound(_boundType, _newVersion[0], _newVersion[1], _newVersion[2]);
    }

    /**
     * @notice Used to get the lower bound
     * @return lower bound
     */
    function getLowerSTVersionBounds() external view returns(uint8[] memory) {
        return VersionUtils.unpack(compatibleSTVersionRange["lowerBound"]);
    }

    /**
     * @notice Used to get the upper bound
     * @return upper bound
     */
    function getUpperSTVersionBounds() external view returns(uint8[] memory) {
        return VersionUtils.unpack(compatibleSTVersionRange["upperBound"]);
    }

    /**
     * @notice Get the setup cost of the module
     */
    function setupCostInPoly() public returns (uint256) {
        if (isCostInPoly)
            return setupCost;
        uint256 cloverRate = IOracle(cloverpatchmathRegistry.getAddress(CLOVERPATCH_ORACLE)).getPrice();
        return DecimalMath.div(setupCost, cloverRate);
    }

    /**
     * @notice Calculates fee in CLOVERS
     */
    function _takeFee() internal returns(uint256) {
        uint256 polySetupCost = setupCostInClovers();
        address cloverpatchToken = cloverpatchmathRegistry.getAddress("CloverPatchToken");
        if (cloverpatchSetupCost > 0) {
            require(IERC20(cloverpatchToken).transferFrom(msg.sender, owner(), cloverpatchSetupCost), "Insufficient allowance for module fee");
        }
        return cloverpatchSetupCost;
    }

    /**
     * @notice Used to initialize the module
     * @param _module Address of module
     * @param _data Data used for the intialization of the module factory variables
     */
    function _initializeModule(address _cloverpatch, bytes memory _data) internal {
        uint256 cloverpatchSetupCost = _takeFee();
        bytes4 initFunction = ICloverPatch(_cloverpatch).getInitFunction();
        if (initFunction != bytes4(0)) {
            require(Util.getSig(_data) == initFunction, "Provided data is not valid");
            /*solium-disable-next-line security/no-low-level-calls*/
            (bool success, ) = _cloverpatch.call(_data);
            require(success, "Unsuccessful initialization");
        }
        /*solium-disable-next-line security/no-block-members*/
        emit GenerateCloverPatchFromFactory(_cloverpatch, name, address(this), msg.sender, setupCost, cloverpatchSetupCost);
    }

}
