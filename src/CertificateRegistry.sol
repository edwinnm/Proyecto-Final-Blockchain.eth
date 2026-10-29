// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title CertificateRegistry
/// @notice Registro on-chain de certificados de cursos. Solo guarda el hash del documento
///         (el PDF/metadata vive off-chain), por lo que cualquiera puede verificarlo sin
///         exponer datos personales.
contract CertificateRegistry is AccessControl {
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    struct Certificate {
        address student;
        address issuer;
        uint64 issuedAt;
        uint64 revokedAt; // 0 = vigente
        bytes32 courseId;
        bytes32 documentHash;
    }

    /// @dev Los ids empiezan en 1; 0 significa "no existe".
    uint256 public totalIssued;

    mapping(uint256 id => Certificate) private _certificates;
    /// @dev keccak(student, courseId) => id del certificado vigente (0 si no hay).
    mapping(bytes32 key => uint256 id) public activeCertificateOf;

    event CertificateIssued(
        uint256 indexed id, address indexed student, bytes32 indexed courseId, address issuer, bytes32 documentHash
    );
    event CertificateRevoked(uint256 indexed id, address indexed revokedBy);

    error ZeroAddress();
    error EmptyDocumentHash();
    error AlreadyCertified(address student, bytes32 courseId);
    error CertificateNotFound(uint256 id);
    error AlreadyRevoked(uint256 id);
    error NotAllowedToRevoke(uint256 id, address caller);

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Emite un certificado. Un estudiante solo puede tener un certificado vigente por curso.
    function issueCertificate(address student, bytes32 courseId, bytes32 documentHash)
        external
        onlyRole(ISSUER_ROLE)
        returns (uint256 id)
    {
        if (student == address(0)) revert ZeroAddress();
        if (documentHash == bytes32(0)) revert EmptyDocumentHash();

        bytes32 key = _key(student, courseId);
        if (activeCertificateOf[key] != 0) revert AlreadyCertified(student, courseId);

        id = ++totalIssued;
        _certificates[id] = Certificate({
            student: student,
            issuer: msg.sender,
            issuedAt: uint64(block.timestamp),
            revokedAt: 0,
            courseId: courseId,
            documentHash: documentHash
        });
        activeCertificateOf[key] = id;

        emit CertificateIssued(id, student, courseId, msg.sender, documentHash);
    }

    /// @notice Revoca un certificado. Lo puede hacer el admin o el emisor original (si aún es emisor).
    ///         El registro no se borra: queda como evidencia histórica.
    function revokeCertificate(uint256 id) external {
        Certificate storage cert = _certificates[id];
        if (cert.issuedAt == 0) revert CertificateNotFound(id);
        if (cert.revokedAt != 0) revert AlreadyRevoked(id);

        bool isAdmin = hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        bool isOriginalIssuer = cert.issuer == msg.sender && hasRole(ISSUER_ROLE, msg.sender);
        if (!isAdmin && !isOriginalIssuer) revert NotAllowedToRevoke(id, msg.sender);

        cert.revokedAt = uint64(block.timestamp);
        delete activeCertificateOf[_key(cert.student, cert.courseId)];

        emit CertificateRevoked(id, msg.sender);
    }

    /// @notice Devuelve el certificado y si sigue vigente.
    function getCertificate(uint256 id) external view returns (Certificate memory cert, bool valid) {
        cert = _certificates[id];
        if (cert.issuedAt == 0) revert CertificateNotFound(id);
        valid = cert.revokedAt == 0;
    }

    /// @notice Verificación simple: ¿el id existe, está vigente y su hash coincide con el documento presentado?
    function verify(uint256 id, bytes32 documentHash) external view returns (bool) {
        Certificate storage cert = _certificates[id];
        return cert.issuedAt != 0 && cert.revokedAt == 0 && cert.documentHash == documentHash;
    }

    function _key(address student, bytes32 courseId) private pure returns (bytes32) {
        return keccak256(abi.encode(student, courseId));
    }
}
