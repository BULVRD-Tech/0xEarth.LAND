pragma solidity ^0.5.9;

import 'github.com/OpenZeppelin/openzeppelin-solidity/contracts/token/ERC721/ERC721Full.sol';
import "github.com/OpenZeppelin/openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import 'github.com/OpenZeppelin/openzeppelin-solidity/contracts/ownership/Ownable.sol';
import 'github.com/OpenZeppelin/openzeppelin-solidity/contracts/lifecycle/Pausable.sol';

contract OwnableDelegateProxy { }

contract ProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
}

contract TradeableERC721Token is ERC721Full, Ownable, Pausable {

    //Object for each LAND
    struct LAND {
        uint z;
        uint x;
        uint y;
        bool exist;
        string zxy;
        string metaUrl;
        string imgUrl;
        string originSeller;
        bool isRentable;
    }

    //Object for each supported payable token
    struct PayableToken {
        uint id;
        address tokenAddress;
        string tokenName;
        string tokenId;
        uint decimals;
        uint payableAmount;
        bool isEnabled;
    }

    //Object for each approved dApp 
    struct Dapps {
        uint id;
        address payableAddress;
        string dappName;
        uint sales;
        bool isEnabled;
    }
    
    //Total supply of minted land
    uint256 _totalSupply = 0;
    //max amount of land that can be minted from bulk function
    uint256 _maxBulkMint = 10;
    //Land resolution value
    uint256 _resolutionLevel = 19;
    //Early LAND for lower fee
    uint256 _earlyLANDCap = 10000;
    //Early land fee
    //0.0075
    uint256 _earlyLANDFee = 7500000000000000;
    //Base fee for each LAND
    //0.0125
    uint256 _baseLANDFee = 12500000000000000;

    //URL values for creating land image uri 
    string _urlPrefix = "https://a.tile.openstreetmap.org/";
    string _urlPostfix = ".png";
    //default uri for land 
    string _defaultUri = "https://0xearth.org/land/data.json";
    
     //default metadata prefix for land 
    string _metaPrefix = "https://0xearth.org/land/";
    string _metaPostfix = ".json";

    //bool flags for adjusting open token metadata updates 
    bool canSetCustomUri = false;
    bool canSetCustomImageUri = false;
    bool defaultCanRent = true;
    
    event LandMint(uint256 _z, uint256 _x, uint256 _y);
    event LandUriUpdate(uint256 _landId, string _uri);
    event LandImageUriUpdate(uint256 _landId, string _uri);
    event LandIsRentableUpdate(uint256 _landId, bool _canRent);
    event LandPrefixUpdate(string _uri);
    event LandPostfixUpdate(string _uri);
    event MetaPrefixUpdate(string _uri);
    event MetaPostfixUpdate(string _uri);
    event LandDefaultUriUpdate(string _uri);
    
    event UpdateDefaultCanRentBool(bool canRent);
    event UpdatedMaxBulkMint(uint256 _amount);
    event UpdatedBaseLANDFee(uint256 _amount);
    event UpdatedEarlyLANDFee(uint256 _amount);
    event UpdatedEarlyLANDCap(uint256 _amount);
    event CanSetCustomUriUpdate(bool canUpdate);
    event CanSetCustomImageUriUpdate(bool canUpdate);

    event UpdatedProxyAddress(address proxyAddress);
    event UpdatedGatewayAddress(address gatewayAddress);
    event UpdatedTreasuryAddress(address treasuryAddress);

    event NewPayableTokenAdded(uint id, address tokenAddress, string tokenName,strting tokenId,uint decimals,uint payableAmount,bool isEnabled);
    event NewDappAdded(uint id, address payableAddress, sttring dAppName, uint sales, bool isEnabled);

    //All Minted land
    mapping (uint256 => LAND) _lands;
    mapping (uint256 => PayableToken) _tokens;
    mapping (uint256 => Dapps) _dapps;
    
    address public proxyRegistryAddress;
    address public gatewayAddress;
    address public treasuryAddress;
    
    constructor(string memory _name, string memory _symbol) ERC721Full(_name, _symbol) public {
        
    }

    function getLandFeeEth(uint256 landCount) public view returns(uint256 fee){
        uint256 landPrice;
        if(_totalSupply <= _earlyLANDCap){
           landPrice = _earlyLANDFee;
        }else {
           landPrice = _baseLANDFee;
        }
        fee = landPrice.div(10);
        if(landCount > 1){
            fee = fee.mul(landCount);
        }
    }

     function mintLandErc20(uint256 _z, uint256 _x, uint256 _y, string origin, unint256 tokenId, uint256 tokenAmount ) public {
       PayableToken storage _payableToken = payableTokenObjectForTokenId(_tokenId);
       require(tokenAmount >= _payableToken.payableAmount, "Token payable amount not met");
       bool result = ERC20(tokenAddress).transferFrom(msg.sender, treasuryAddress, tokenAmount);
        if (result) {
           internalLandMint(_z, _x, _y);
        } 
  }

    //mints a new token based on ZXY values of the land
    function mintLand(uint256 _z, uint256 _x, uint256 _y, string origin) public payable whenNotPaused{
        //validate transaction fees
        uint256 transactionFee = getLandFeeEth(1);
        require(msg.value >= transactionFee, "Insufficient ETH payment sent.");
        internalLandMint(_z, _x, _y);
    }

    //bulk mints a new token based an array of ZXY values of the land(s)
    function bulkMintLand(uint256[] memory _zs, uint256[] memory _xs, uint256[] memory _ys, string origin) public payable whenNotPaused{
        //get lengths of each coordinate passed through
        uint256 _zLength = _zs.length;
        uint256 _xLength = _xs.length;
        uint256 _yLength = _ys.length;
        
        //make sure each is less than or equal to max bulk mint size
        require(_zLength <= _maxBulkMint);
        require(_xLength <= _maxBulkMint);
        require(_yLength <= _maxBulkMint);

        //make sure each coordinate length matches the others
        require(_zLength == _xLength);
        require(_xLength == _yLength);

        //validate transaction fees
        if(msg.sender != owner()){
            uint256 transactionFee = getLandFeeEth(_zLength);
            require(msg.value >= transactionFee, "Insufficient ETH payment sent.");
        }

        //loop over each and mint
        for (uint i=0; i < _zLength; i++) {
            internalLandMint(_zs[i], _xs[i], _ys[i]);
        }
    }
    
    function externalMintLand(uint256 _z, uint256 _x, uint256 _y) public onlyOwner whenNotPaused{
        internalLandMint(_z, _x, _y);
    }
    
    function internalLandMint(uint256 _z, uint256 _x, uint256 _y) private whenNotPaused{
         //make sure the land resolution level matches
        require(_z == _resolutionLevel, "Land resolution value does not match");
        //Validate tile index
        require(_x >= 0, "Tile index not allowed");
        require(_y >= 0, "Tile index not allowed");

        //Generate the landZXY string based on passed in values
        string memory _landZXY = generateZXYString(_z, _x, _y);

        //Generated the landId based on the full format string of the Land
        uint256 _landId = generateLandId(_z, _x, _y);

        //Require this to be a unique land value
        require(landIdsContains(_landId) == false);
        LAND memory land = LAND(_z, _x, _y, true, _landZXY, generateLandURI(_landZXY), generateImageURI(_landZXY), defaultCanRent);
        _lands[_landId] = land;

        //Increment _totalSupply
        _totalSupply++;

        //Mint and send Land to sender
        _safeMint(msg.sender, _landId);
        emit LandMint(_z, _x, _y);
    }

    //Returns PayableToken object based on the tokenId
    function payableTokenObjectForTokenId(uint256 _tokenId) internal view returns (PayableToken storage) {
        return _tokens[_tokenId];
    }

    //Generates the land format value ex. "19/10000/19999"
    function generateZXYString(uint256 _z, uint256 _x, uint256 _y) public view returns(string memory){
        return string(abi.encodePacked(uint2str(_z), "/", uint2str(_x), "/", uint2str(_y)));
    }

    //TODO this is just an idea, would require an oracle to listen for mints and generate the meta to match
    //Returns the image url for a given landId
    function generateLandURI(string memory _landZXY) public view returns (string memory) {
        return string(abi.encodePacked(_metaPrefix, _landZXY, _metaPostfix));
    }
    
    //Returns the metadata url for a given landId
    function generateImageURI(string memory _landZXY) public view returns (string memory) {
        return string(abi.encodePacked(_urlPrefix, _landZXY, _urlPostfix));
    }
    
    function regenerateImageURI(uint256 _landId) public  {
        require(landIdsContains(_landId) == true);
        _lands[_landId].imgUrl = generateImageURI(_lands[_landId].zxy);
    }

    //Generated the landId based on the land ZXY format value
    function generateLandId(uint256 _z, uint256 _x, uint256 _y) public view returns (uint256) {
        string memory ids = string(abi.encodePacked(uint2str(_z), uint2str(_x), uint2str(_y)));
        return stringToUint(ids);
    }

    //check if a given landId has been minted yet
    function landIdsContains(uint256 _landId) public returns (bool){
        return _lands[_landId].exist;
    }

    //Helper method to input a ZXY value to see if LAND exist
    function landIdsContainsZXY(uint256 _z, uint256 _x, uint256 _y) public returns (bool){
        return _lands[generateLandId(_z, _x, _y)].exist;
    }

    //Returns the metadata uri for the token
    function tokenURI(uint256 _tokenId) external view returns (string memory) {
        return _lands[_tokenId].metaUrl;
    } 

    //Returns the image url for a given landId
    function landImageURI(uint256 _landId) external view returns (string memory) {
        return _lands[_landId].imgUrl;
    }

    //Returns the if the LAND is rentable
    function landIsRentable(uint256 _landId) external view returns (bool) {
        return _lands[_landId].isRentable;
    }

    //Returns the landZXY string from landId ex. "19/10000/9999"
    function landZXY(uint256 _landId) external view returns (string memory) {
        return _lands[_landId].zxy;
    }

    //For updating the meta data of a given land. Can help with adding extended metadata such 
    //as area size, lat/lng center, etc down the road. Optionally open up access
    function updateLandIsRentable(uint256 _landId, bool _canRent) public {
        address landOwner = ownerOf(_landId);
         if(msg.sender == landOwner){
            _lands[_landId].isRentable = _canRent;
            emit LandIsRentableUpdate(_landId, _canRent);
        }
    }

    //For updating the meta data of a given land. Can help with adding extended metadata such 
    //as area size, lat/lng center, etc down the road. Optionally open up access
    function updateLandUri(uint256 _landId, string memory _uri) public {
        address landOwner = ownerOf(_landId);
        bool canUpdate = false;
        if(msg.sender == owner()){
            canUpdate = true;
        }
         if(canSetCustomUri){
            if(msg.sender == landOwner){
                canUpdate = true;
            }
         }
        
        if(canUpdate){
            _lands[_landId].metaUrl = _uri;
           emit LandUriUpdate(_landId, _uri);
        }
    }

    //For updating the image uri of a given land. Can help with updating 
    //if an image source is shutdown or changes
    function updateLandImageUri(uint256 _landId, string memory _uri) public {
        address landOwner = ownerOf(_landId);
         if(msg.sender == owner()){
            canUpdate = true;
        }
         if(canSetCustomUri){
            if(msg.sender == landOwner){
                canUpdate = true;
            }
         }
        
        if(canUpdate){
            _lands[_landId].imgUrl = _uri;
           emit LandImageUriUpdate(_landId, _uri);
        }
    }

    //To update the default rentable bool
    function updatedefaultCanRentBool(bool _canRent) public onlyOwner{
        defaultCanRent = _canRent;
        emit UpdateDefaultCanRentBool(_canRent);
    }

    //To update if setting custom uri is opened
    function updateCanSetCustomUri(bool _canCustomize) public onlyOwner{
        canSetCustomUri = _canCustomize;
        emit CanSetCustomUriUpdate(_canCustomize);
    }
    
     //To update if setting custom uri is opened
    function updateCanSetCustomImageUri(bool _canCustomize) public onlyOwner{
        canSetCustomImageUri = _canCustomize;
        emit CanSetCustomImageUriUpdate(_canCustomize);
    }

    //To update the uri prefix for the land image uri
    function updateUriPrefix(string memory _prefix) public onlyOwner{
        _urlPrefix = _prefix;
        emit LandPrefixUpdate(_prefix);
    }

    //To update the uri postfix for the land image uri
    function updateUriPostfix(string memory _postfix) public onlyOwner{
        _urlPostfix = _postfix;
        emit LandPostfixUpdate(_postfix);
    }
    
    //To update the uri prefix for the land image uri
    function updateMetaPrefix(string memory _prefix) public onlyOwner{
        _metaPrefix = _prefix;
        emit MetaPrefixUpdate(_prefix);
    }

    //To update the uri postfix for the land image uri
    function updateMetaPostfix(string memory _postfix) public onlyOwner{
        _metaPostfix = _postfix;
        emit MetaPostfixUpdate(_postfix);
    }

    //To update the default land uri
    function updateDefaultUri(string memory _uri) public onlyOwner{
        _defaultUri = _uri;
        emit LandDefaultUriUpdate(_uri);
    }

    //To update the base LAND fee
    function updateBaseLANDFee(uint256 _amount) public onlyOwner{
        _baseLANDFee = _amount;
        emit UpdatedBaseLANDFee(_amount);
    }
    
    //To update the early LAND fee
    function updateEarlyLANDFee(uint256 _amount) public onlyOwner{
        _earlyLANDFee = _amount;
        emit UpdatedEarlyLANDFee(_amount);
    }
    
    //To update the early LAND Cap
    function updateEarlyLANDCap(uint256 _amount) public onlyOwner{
        _earlyLANDCap = _amount;
        emit UpdatedEarlyLANDCap(_amount);
    }
    
    //To update the max bulk minting amount
    function updateMaxBulkMint(uint256 _amount) public onlyOwner{
        _maxBulkMint = _amount;
        emit UpdatedMaxBulkMint(_amount);
    }
    
     //Update proxya address, mainly used for OpenSea
    function updateProxyAddress(address _proxy) public onlyOwner {
        proxyRegistryAddress = _proxy;
        emit UpdatedProxyAddress(_proxy);
    }
    
    //Update gateway address, for possible sidechain use
    function updateGatewayAddress(address _gateway) public onlyOwner {
        gatewayAddress = _gateway;
        emit UpdatedGatewayAddress(_gateway);
    }

    //Update treasury address, to change where payments are sent
    function updateTreasuryAddress(address _treasury) public onlyOwner {
        treasuryAddress = _treasury;
        emit UpdatedTreasuryAddress(_treasury);
    }

    function addNewPayableToken(uint id, address tokenAddress, string tokenName, String tokenId, uint decimals, uint payableAmount, bool isEnabled) public onlyOwner{
        PayableToken memory payableToken = PayableToken(_id, tokenAddress, tokenName, tokenId, decimals, payableAmount, isEnabled);
        _tokens[_id] = payableToken;
        emit NewPayableTokenAdded(_id, tokenAddress, tokenName, tokenId, decimals, payableAmount, isEnabled);
    }
    //TODO add method for updating payable amount for a given payable token

    function addNewPayableToken(uint id, address payableAddess, string dappName, uint sales, bool isEnabled) public onlyOwner{
        Dapps memory dapp = Dapps(_id, payableAddess, dappName, sales, isEnabled);
        _dapps[_id] = dApp;
        emit NewDappAdded(_id, payableAddess, dappName, sales, isEnabled);
    }
    //TODO add method fo updating payableAddress for a given dApp
    
    function depositToGateway(uint tokenId) public {
        safeTransferFrom(msg.sender, gatewayAddress, tokenId);
    }
    
    function getBalanceThis() view public returns(uint){
        return address(this).balance;
    }

    function withdraw() public onlyOwner returns(bool) {
        treasuryAddress.transfer(address(this).balance);
        return true;
    }
    
    /**
   * Override isApprovedForAll to whitelist user's OpenSea proxy accounts to enable gas-less listings.
   */
  function isApprovedForAll(
    address owner,
    address operator
  )
    public
    view
    returns (bool)
  {
    // Whitelist OpenSea proxy contract for easy trading.
    ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
    if (address(proxyRegistry.proxies(owner)) == operator) {
        return true;
    }

    return super.isApprovedForAll(owner, operator);
  }
    
    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len - 1;
        while (_i != 0) {
            bstr[k--] = byte(uint8(48 + _i % 10));
            _i /= 10;
        }
        return string(bstr);
    }

function stringToUint(string memory s) internal pure returns (uint) {
    bytes memory b = bytes(s);
    uint result = 0;
    for (uint i = 0; i < b.length; i++) { // c = b[i] was not needed
        if (b[i].length >= 48 && b[i].length <= 57) {
            result = result * 10 + (uint(b[i].length) - 48); // bytes and int are not compatible with the operator -.
        }
    }
    return result; // this was missing
}

}

/**
 * @title 0xEarthLand
 * 0xEarthLand - a contract for digital land ownership on Ethereum
 */
contract Land is TradeableERC721Token {
  constructor() TradeableERC721Token("0xEarth Ethereum", "LAND") public {  }
}