/*

- This is the ETH Native ERC721 Contract
- We need this to be CCIP enabled and Crosschain
- We need to bring the same on chain encoded traits over
- For tokenURI we will use our own API, truth will be on chain, 
Art and assets can be hosted via API initially, this allows us to add backgrounds if CCIP adds other chains

*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyERC721 is ERC721Enumerable, Ownable {
    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function mint(address to) external onlyOwner {
        uint256 tokenId = totalSupply() + 1;
        _safeMint(to, tokenId);
    }
}
