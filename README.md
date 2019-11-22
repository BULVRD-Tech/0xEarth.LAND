# 0xEarth.LAND
Fully trustless ERC-721 standard representing digitized plots of land of earth. 

Each token is a unique representation of a bounding box based on the ZXY map tile standard. Current implementation uses 
a zoom level of 19, which correlates to 274.9 billion unique land plots. 

The token standard currently implements helper methods making it easy to query the values of each token and it's correlative 
land metadata. Using the ZXY standard makes it simple to reverse query back to a lat / lng value. Further implementation
references can be found at https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
