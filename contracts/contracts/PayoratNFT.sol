// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC7857} from "./interfaces/IERC7857.sol";
import {IERC7857Metadata} from "./interfaces/IERC7857Metadata.sol";
import {IERC7857DataVerifier, PreimageProofOutput, TransferValidityProofOutput} from "./interfaces/IERC7857DataVerifier.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title PayoraNFT
/// @notice An ERC-7857 iNFT representing an AI pay allocation agent.
///         Each token stores data hashes pointing to 0G Storage where the agent's
///         config, bills, goals, and decision history live.
///         The agent learns from user overrides stored in its decision log.
contract PayoraNFT is
    AccessControlEnumerableUpgradeable,
    IERC7857,
    IERC7857Metadata
{
    event Approval(
        address indexed _from,
        address indexed _to,
        uint256 indexed _tokenId
    );
    event ApprovalForAll(
        address indexed _owner,
        address indexed _operator,
        bool _approved
    );

    /// @custom:storage-location erc7201:Payora.storage.PayoraNFT
    struct PayoraNFTStorage {
        // Token data
        mapping(uint256 => TokenData) tokens;
        mapping(address owner => mapping(address operator => bool)) operatorApprovals;
        uint256 nextTokenId;
        // Contract metadata
        string name;
        string symbol;
        string chainURL;
        string indexerURL;
        // Core components
        IERC7857DataVerifier verifier;
    }

    struct TokenData {
        address owner;
        string[] dataDescriptions;
        bytes32[] dataHashes;
        address[] authorizedUsers;
        address approvedUser;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // keccak256(abi.encode(uint(keccak256("Payora.storage.PayoraNFT")) - 1)) & ~bytes32(uint(0xff))
    bytes32 private constant Payora_STORAGE_LOCATION =
        0xb2c5e5a5d0e7c7f8a1b3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f400;

    function _getPayoraStorage()
        private
        pure
        returns (PayoraNFTStorage storage $)
    {
        assembly {
            $.slot := Payora_STORAGE_LOCATION
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address verifierAddr,
        string memory chainURL_,
        string memory indexerURL_
    ) public virtual initializer {
        require(verifierAddr != address(0), "Zero address");

        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        PayoraNFTStorage storage $ = _getPayoraStorage();
        $.name = name_;
        $.symbol = symbol_;
        $.chainURL = chainURL_;
        $.indexerURL = indexerURL_;
        $.verifier = IERC7857DataVerifier(verifierAddr);
    }

    // =========================================================================
    // View functions
    // =========================================================================

    function name() public view virtual returns (string memory) {
        return _getPayoraStorage().name;
    }

    function symbol() public view virtual returns (string memory) {
        return _getPayoraStorage().symbol;
    }

    function verifier() public view virtual returns (IERC7857DataVerifier) {
        return _getPayoraStorage().verifier;
    }

    function ownerOf(uint256 tokenId) public view virtual returns (address) {
        PayoraNFTStorage storage $ = _getPayoraStorage();
        TokenData storage token = $.tokens[tokenId];
        require(token.owner != address(0), "Token not exist");
        return token.owner;
    }

    function authorizedUsersOf(
        uint256 tokenId
    ) public view virtual returns (address[] memory) {
        PayoraNFTStorage storage $ = _getPayoraStorage();
        TokenData storage token = $.tokens[tokenId];
        require(token.owner != address(0), "Token not exist");
        return token.authorizedUsers;
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual returns (string memory) {
        PayoraNFTStorage storage $ = _getPayoraStorage();
        require(_exists(tokenId), "Token does not exist");

        return
            string(
                abi.encodePacked(
                    '{"chainURL":"',
                    $.chainURL,
                    '","indexerURL":"',
                    $.indexerURL,
                    '","tokenId":"',
                    Strings.toString(tokenId),
                    '"}'
                )
            );
    }

    function dataHashesOf(
        uint256 tokenId
    ) public view virtual returns (bytes32[] memory) {
        PayoraNFTStorage storage $ = _getPayoraStorage();
        TokenData storage token = $.tokens[tokenId];
        require(token.owner != address(0), "Token not exist");
        return token.dataHashes;
    }

    function dataDescriptionsOf(
        uint256 tokenId
    ) public view virtual returns (string[] memory) {
        PayoraNFTStorage storage $ = _getPayoraStorage();
        TokenData storage token = $.tokens[tokenId];
        require(token.owner != address(0), "Token not exist");
        return token.dataDescriptions;
    }

    function getApproved(
        uint256 tokenId
    ) public view virtual returns (address operator) {
        return _getPayoraStorage().tokens[tokenId].approvedUser;
    }

    function isApprovedForAll(
        address owner,
        address operator
    ) public view virtual returns (bool) {
        return _getPayoraStorage().operatorApprovals[owner][operator];
    }

    // =========================================================================
    // Admin functions
    // =========================================================================

    function updateVerifier(
        address newVerifier
    ) public virtual onlyRole(ADMIN_ROLE) {
        require(newVerifier != address(0), "Zero address");
        _getPayoraStorage().verifier = IERC7857DataVerifier(newVerifier);
    }

    function updateURLs(
        string memory newChainURL,
        string memory newIndexerURL
    ) public virtual onlyRole(ADMIN_ROLE) {
        PayoraNFTStorage storage $ = _getPayoraStorage();
        $.chainURL = newChainURL;
        $.indexerURL = newIndexerURL;
    }

    // =========================================================================
    // ERC-7857: Mint
    // =========================================================================

    function mint(
        bytes[] calldata proofs,
        string[] calldata dataDescriptions,
        address to
    ) public payable virtual returns (uint256 tokenId) {
        PayoraNFTStorage storage $ = _getPayoraStorage();

        require(
            dataDescriptions.length == proofs.length,
            "Descriptions and proofs length mismatch"
        );

        if (to == address(0)) {
            to = msg.sender;
        }

        PreimageProofOutput[] memory proofOutput = $.verifier.verifyPreimage(
            proofs
        );
        bytes32[] memory dataHashes = new bytes32[](proofOutput.length);

        for (uint i = 0; i < proofOutput.length; i++) {
            require(
                proofOutput[i].isValid,
                string(
                    abi.encodePacked(
                        "Invalid preimage proof at index ",
                        Strings.toString(i)
                    )
                )
            );
            dataHashes[i] = proofOutput[i].dataHash;
        }

        tokenId = $.nextTokenId++;
        $.tokens[tokenId] = TokenData({
            owner: to,
            dataHashes: dataHashes,
            dataDescriptions: dataDescriptions,
            authorizedUsers: new address[](0),
            approvedUser: address(0)
        });

        emit Minted(tokenId, msg.sender, to, dataHashes, dataDescriptions);
    }

    // =========================================================================
    // ERC-7857: Update (IERC7857Metadata)
    // =========================================================================

    function update(uint256 tokenId, bytes[] calldata proofs) public virtual {
        PayoraNFTStorage storage $ = _getPayoraStorage();
        TokenData storage token = $.tokens[tokenId];
        require(token.owner == msg.sender, "Not owner");

        PreimageProofOutput[] memory proofOutput = $.verifier.verifyPreimage(
            proofs
        );
        bytes32[] memory newDataHashes = new bytes32[](proofOutput.length);

        for (uint i = 0; i < proofOutput.length; i++) {
            require(proofOutput[i].isValid, "Invalid preimage proof");
            newDataHashes[i] = proofOutput[i].dataHash;
        }

        bytes32[] memory oldDataHashes = token.dataHashes;
        token.dataHashes = newDataHashes;

        emit Updated(tokenId, oldDataHashes, newDataHashes);
    }

    // =========================================================================
    // ERC-7857: Transfer
    // =========================================================================

    function transfer(
        address to,
        uint256 tokenId,
        bytes[] calldata proofs
    ) public virtual {
        PayoraNFTStorage storage $ = _getPayoraStorage();
        require(to != address(0), "Zero address");
        require($.tokens[tokenId].owner == msg.sender, "Not owner");

        TransferValidityProofOutput[] memory proofOutput = $
            .verifier
            .verifyTransferValidity(proofs);
        bytes16[] memory sealedKeys = new bytes16[](proofOutput.length);
        bytes32[] memory newDataHashes = new bytes32[](proofOutput.length);

        for (uint i = 0; i < proofOutput.length; i++) {
            require(
                proofOutput[i].isValid &&
                    proofOutput[i].oldDataHash ==
                    $.tokens[tokenId].dataHashes[i] &&
                    proofOutput[i].receiver == to,
                "Invalid transfer proof"
            );
            sealedKeys[i] = proofOutput[i].sealedKey;
            newDataHashes[i] = proofOutput[i].newDataHash;
        }

        $.tokens[tokenId].owner = to;
        $.tokens[tokenId].dataHashes = newDataHashes;

        emit Transferred(tokenId, msg.sender, to);
        emit PublishedSealedKey(to, tokenId, sealedKeys);
    }

    // =========================================================================
    // ERC-7857: Clone
    // =========================================================================

    function clone(
        address to,
        uint256 tokenId,
        bytes[] calldata proofs
    ) public virtual returns (uint256) {
        PayoraNFTStorage storage $ = _getPayoraStorage();
        require(to != address(0), "Zero address");
        require($.tokens[tokenId].owner == msg.sender, "Not owner");

        TransferValidityProofOutput[] memory proofOutput = $
            .verifier
            .verifyTransferValidity(proofs);
        bytes32[] memory newDataHashes = new bytes32[](proofOutput.length);
        bytes16[] memory sealedKeys = new bytes16[](proofOutput.length);

        for (uint i = 0; i < proofOutput.length; i++) {
            require(
                proofOutput[i].isValid &&
                    proofOutput[i].oldDataHash ==
                    $.tokens[tokenId].dataHashes[i] &&
                    proofOutput[i].receiver == to,
                "Invalid clone proof"
            );
            sealedKeys[i] = proofOutput[i].sealedKey;
            newDataHashes[i] = proofOutput[i].newDataHash;
        }

        uint256 newTokenId = $.nextTokenId++;
        $.tokens[newTokenId] = TokenData({
            owner: to,
            dataHashes: newDataHashes,
            dataDescriptions: $.tokens[tokenId].dataDescriptions,
            authorizedUsers: new address[](0),
            approvedUser: address(0)
        });

        emit Cloned(tokenId, newTokenId, msg.sender, to);
        emit PublishedSealedKey(to, newTokenId, sealedKeys);
        return newTokenId;
    }

    // =========================================================================
    // ERC-7857: Authorization
    // =========================================================================

    function authorizeUsage(uint256 tokenId, address to) public virtual {
        PayoraNFTStorage storage $ = _getPayoraStorage();
        require($.tokens[tokenId].owner == msg.sender, "Not owner");
        $.tokens[tokenId].authorizedUsers.push(to);
        emit Authorization(msg.sender, to, tokenId);
    }

    // =========================================================================
    // ERC-721-like: Approvals
    // =========================================================================

    function approve(address to, uint256 tokenId) public virtual {
        PayoraNFTStorage storage $ = _getPayoraStorage();
        require($.tokens[tokenId].owner == msg.sender, "Not owner");
        $.tokens[tokenId].approvedUser = to;
        emit Approval(msg.sender, to, tokenId);
    }

    function setApprovalForAll(address to, bool approved) public virtual {
        _getPayoraStorage().operatorApprovals[msg.sender][to] = approved;
        emit ApprovalForAll(msg.sender, to, approved);
    }

    // =========================================================================
    // Internal
    // =========================================================================

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _getPayoraStorage().tokens[tokenId].owner != address(0);
    }

    string public constant VERSION = "1.0.0";
}