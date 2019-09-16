pragma solidity ^0.5.6;

import 'github.com/OpenZeppelin/openzeppelin-solidity/contracts/token/ERC721/ERC721Full.sol';
import 'github.com/OpenZeppelin/openzeppelin-solidity/contracts/ownership/Ownable.sol';
import 'github.com/OpenZeppelin/openzeppelin-solidity/contracts/lifecycle/Pausable.sol';

contract TradeableERC721Token is ERC721Full, Ownable, Pausable {

    //Total supply of minted land
    uint256 _totalSupply = 0;
    //max amount of land that can be minted from bulk function
    uint256 _maxBulkMint = 10;
    //Land resolution value
    uint256 _resolutionLevel = 19;
    //Base fee for each LAND
    uint256 _baseLANDFee = 15;

    //URL values for creating land image uri 
    string _urlPrefix = "https://a.tile.openstreetmap.org/";
    string _urlPostfix = ".png";
    //default uri for land 
    string _defaultUri = "https://raw.githubusercontent.com/BULVRD-Tech/0xEarth.LAND/master/Klaytn/land.json";

    //bool flags for adjusting open token metadata updates 
    bool canSetCustomUri = false;
    bool canSetCustomImageUri = false;
    
    event LandMint(uint256 _z, uint256 _x, uint256 _y);
    event LandUriUpdate(uint256 _landId, string _uri);
    event LandImageUriUpdate(uint256 _landId, string _uri);
    event LandPrefixUpdate(string _uri);
    event LandPostfixUpdate(string _uri);
    event LandDefaultUriUpdate(string _uri);
    
    event UpdatedMaxBulkMint(uint256 _amount);
    event UpdatedBaseLANDFee(uint256 _amount);
    event CanSetCustomUriUpdate(bool canUpdate);
    event CanSetCustomImageUriUpdate(bool canUpdate);

    //tracking of minted land 
    mapping (uint256 => bool) _landIds;
    //storing of ZXY of minted land
    mapping (uint256 => string) _landZXYs;
    //storing of land metadata uris 
    mapping (uint256 => string) _landUris;
    //storing of reference image for each land 
    mapping (uint256 => string) _landImages;
    
    constructor(string memory _name, string memory _symbol) ERC721Full(_name, _symbol) public {
        
    }

    function getLandFee(uint256 landCount) public view returns(uint256 fee){
        uint256 landPrice = _baseLANDFee;
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
            require(msg.value >= transactionFee, "Insufficient KLAY fee sent.");
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
            require(msg.value >= transactionFee, "Insufficient KLAY fee sent.");
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

        //Generate the landZXY string based on passed in values
        string memory _landZXY = generateZXYString(_z, _x, _y);

        //Generated the landId based on the full format string of the Land
        uint256 _landId = generateLandId(_landZXY);

        //Require this to be a unique land value
        require(landIdsContains(_landId) == false);

        //Store the minting of this landId
        _landIds[_landId] = true;

        //Store the landZXY string against the landId
        _landZXYs[_landId] = _landZXY;

        //Set uri for the given landId
        _landUris[_landId] = _defaultUri;

        //Set uri for the given landId
        _landImages[_landId] = generateImageURI(_landZXY);

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

    //Returns the image url for a given landId
    function generateImageURI(string memory _landZXY) public view returns (string memory) {
        return string(abi.encodePacked(_urlPrefix, _landZXY, _urlPostfix));
    }

    //Generated the landId based on the land ZXY format value
    function generateLandId(string memory _zxy) public view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_zxy)));
    }

    //check if a given landId has been minted yet
    function landIdsContains(uint256 _landId) public view returns (bool){
        return _landIds[_landId];
    }

    //Returns the metadata uri for the token
    function tokenURI(uint256 _tokenId) external view returns (string memory) {
        return _landUris[_tokenId];
    } 

    //Returns the image url for a given landId
    function landImageURI(uint256 _landId) external view returns (string memory) {
        return _landImages[_landId];
    }

    //Returns the landZXY string from landId ex. "19/10000/9999"
    function landZXY(uint256 _landId) external view returns (string memory) {
        return _landZXYs[_landId];
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
           _landUris[_landId] = _uri;
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
           _landImages[_landId] = _uri;
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

    //To update the default land uri
    function updateDefaultUri(string memory _uri) public onlyOwner{
        _defaultUri = _uri;
        emit LandDefaultUriUpdate(_uri);
    }

    //To update the max bulk minting amount
    function updateMaxBulkMint(uint256 _amount) public onlyOwner{
        _maxBulkMint = _amount;
        emit UpdatedMaxBulkMint(_amount);
    }

    //To update the max bulk minting amount
    function updateBaseLANDFee(uint256 _amount) public onlyOwner{
        _baseLANDFee = _amount;
        emit UpdatedBaseLANDFee(_amount);
    }
    
    function getBalanceThis() view public returns(uint){
        return address(this).balance;
    }

    function withdraw() public onlyOwner returns(bool) {
        msg.sender.transfer(address(this).balance);
        return true;
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

}

/**
 * @title 0xEarthLand
 * 0xEarthLand - a contract for digital land ownership.
 */
contract Land is TradeableERC721Token {
  constructor() TradeableERC721Token("0xEarth", "LAND") public {  }
}