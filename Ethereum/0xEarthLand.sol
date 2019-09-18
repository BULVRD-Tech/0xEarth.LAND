pragma solidity ^0.5.9;

import 'github.com/OpenZeppelin/openzeppelin-solidity/contracts/token/ERC721/ERC721Full.sol';
import 'github.com/OpenZeppelin/openzeppelin-solidity/contracts/ownership/Ownable.sol';
import 'github.com/OpenZeppelin/openzeppelin-solidity/contracts/lifecycle/Pausable.sol';

contract OwnableDelegateProxy { }

contract ProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
}

contract TradeableERC721Token is ERC721Full, Ownable, Pausable {

    struct LAND {
        uint z;
        uint x;
        uint y;
        bool exist;
        string zxy;
        string metaUrl;
        string imgUrl;
    }
    
    //Total supply of minted land
    uint256 _totalSupply = 0;
    //max amount of land that can be minted from bulk function
    uint256 _maxBulkMint = 10;
    //Land resolution value
    uint256 _resolutionLevel = 19;
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
    
    event LandMint(uint256 _z, uint256 _x, uint256 _y);
    event LandUriUpdate(uint256 _landId, string _uri);
    event LandImageUriUpdate(uint256 _landId, string _uri);
    event LandPrefixUpdate(string _uri);
    event LandPostfixUpdate(string _uri);
    event MetaPrefixUpdate(string _uri);
    event MetaPostfixUpdate(string _uri);
    event LandDefaultUriUpdate(string _uri);
    
    event UpdatedMaxBulkMint(uint256 _amount);
    event UpdatedBaseLANDFee(uint256 _amount);
    event CanSetCustomUriUpdate(bool canUpdate);
    event CanSetCustomImageUriUpdate(bool canUpdate);

    //All Minted land
    mapping (uint256 => LAND) _lands;
    
    address proxyRegistryAddress;
    
    constructor(string memory _name, string memory _symbol, address _proxyRegistryAddress) ERC721Full(_name, _symbol) public {
        proxyRegistryAddress = _proxyRegistryAddress;
    }

    function getLandFee(uint256 landCount) public view returns(uint256 fee){
        uint256 landPrice;
        if(_totalSupply <= 10000){
           landPrice = _earlyLANDFee;
        }else {
           landPrice = _baseLANDFee;
        }
        fee = landPrice.div(10);
        if(landCount > 1){
            fee = fee.mul(landCount);
        }
    }

    //mints a new token based on ZXY values of the land
    function mintLand(uint256 _z, uint256 _x, uint256 _y) public payable whenNotPaused{
        //validate transaction fees
        if(msg.sender != owner()){
            uint256 transactionFee = getLandFee(1);
            require(msg.value >= transactionFee, "Insufficient ETH payment sent.");
        }

        internalLandMint(_z, _x, _y);
    }

    //bulk mints a new token based an array of ZXY values of the land(s)
    function bulkMintLand(uint256[] memory _zs, uint256[] memory _xs, uint256[] memory _ys) public payable whenNotPaused{
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
            uint256 transactionFee = getLandFee(_zLength);
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
        LAND memory land = LAND(_z, _x, _y, true, _landZXY, generateLandURI(_landZXY), generateImageURI(_landZXY));
        _lands[_landId] = land;

        //Increment _totalSupply
        _totalSupply++;

        //Mint and send Land to sender
        _safeMint(msg.sender, _landId);
        emit LandMint(_z, _x, _y);
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

    //Returns the metadata uri for the token
    function tokenURI(uint256 _tokenId) external view returns (string memory) {
        return _lands[_tokenId].metaUrl;
    } 

    //Returns the image url for a given landId
    function landImageURI(uint256 _landId) external view returns (string memory) {
        return _lands[_landId].imgUrl;
    }

    //Returns the landZXY string from landId ex. "19/10000/9999"
    function landZXY(uint256 _landId) external view returns (string memory) {
        return _lands[_landId].zxy;
    }

    //For updating the meta data of a given land. Can help with adding extended metadata such 
    //as area size, lat/lng center, etc down the road. Optionally open up access
    function updateLandUri(uint256 _landId, string memory _uri) public {
        bool canUpdate = canSetCustomUri;

        address landOwner = ownerOf(_landId);
        if(msg.sender == landOwner){
            canUpdate = true;
        }
        
        if(msg.sender == owner()){
           canUpdate = true;
        }

        if(canUpdate){
           _lands[_landId].metaUrl = _uri;
           emit LandUriUpdate(_landId, _uri);
        }
    }

    //For updating the image uri of a given land. Can help with updating 
    //if an image source is shutdown or changes
    function updateLandImageUri(uint256 _landId, string memory _uri) public {
        bool canUpdate = canSetCustomImageUri;

        address landOwner = ownerOf(_landId);
        if(msg.sender == landOwner){
            canUpdate = true;
        }
        
        if(msg.sender == owner()){
           canUpdate = true;
        }

        if(canUpdate){
           _lands[_landId].imgUrl = _uri;
           emit LandImageUriUpdate(_landId, _uri);
        }
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

    //To update the max bulk minting amount
    function updateBaseLANDFee(uint256 _amount) public onlyOwner{
        _baseLANDFee = _amount;
        emit UpdatedBaseLANDFee(_amount);
    }
    
    //To update the max bulk minting amount
    function updateMaxBulkMint(uint256 _amount) public onlyOwner{
        _maxBulkMint = _amount;
        emit UpdatedMaxBulkMint(_amount);
    }
    
    function getBalanceThis() view public returns(uint){
        return address(this).balance;
    }

    function withdraw() public onlyOwner returns(bool) {
        msg.sender.transfer(address(this).balance);
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
 * 0xEarthLand - a contract for digital land ownership.
 */
contract Land is TradeableERC721Token {
  constructor(address _proxyRegistryAddress) TradeableERC721Token("0xEarth", "LAND", _proxyRegistryAddress) public {  }
}