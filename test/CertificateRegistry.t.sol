// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {CertificateRegistry} from "../src/CertificateRegistry.sol";

contract CertificateRegistryTest is Test {
    CertificateRegistry registry;

    address admin = makeAddr("admin");
    address issuer = makeAddr("issuer");
    address otherIssuer = makeAddr("otherIssuer");
    address student = makeAddr("student");
    address stranger = makeAddr("stranger");

    bytes32 constant COURSE = keccak256("SOLIDITY-101");
    bytes32 constant DOC = keccak256("certificado.pdf");

    event CertificateIssued(
        uint256 indexed id, address indexed student, bytes32 indexed courseId, address issuer, bytes32 documentHash
    );
    event CertificateRevoked(uint256 indexed id, address indexed revokedBy);

    function setUp() public {
        registry = new CertificateRegistry(admin);
        bytes32 issuerRole = registry.ISSUER_ROLE();
        vm.startPrank(admin);
        registry.grantRole(issuerRole, issuer);
        registry.grantRole(issuerRole, otherIssuer);
        vm.stopPrank();
    }

    // ---------- helpers ----------
    function _issue() internal returns (uint256) {
        vm.prank(issuer);
        return registry.issueCertificate(student, COURSE, DOC);
    }

    function _unauthorized(address who, bytes32 role) internal {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, who, role));
    }

    // ---------- constructor / roles ----------
    function test_Constructor_GrantsAdmin() public view {
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(registry.hasRole(registry.ISSUER_ROLE(), admin));
    }

    function test_Constructor_RevertsOnZeroAdmin() public {
        vm.expectRevert(CertificateRegistry.ZeroAddress.selector);
        new CertificateRegistry(address(0));
    }

    function test_OnlyAdminCanGrantIssuer() public {
        bytes32 role = registry.ISSUER_ROLE();
        _unauthorized(stranger, registry.DEFAULT_ADMIN_ROLE());
        vm.prank(stranger);
        registry.grantRole(role, stranger);
    }

    // ---------- issue ----------
    function test_Issue_StoresCertificate() public {
        vm.warp(1_700_000_000);
        uint256 id = _issue();

        assertEq(id, 1);
        assertEq(registry.totalIssued(), 1);
        (CertificateRegistry.Certificate memory c, bool valid) = registry.getCertificate(id);
        assertTrue(valid);
        assertEq(c.student, student);
        assertEq(c.issuer, issuer);
        assertEq(c.issuedAt, 1_700_000_000);
        assertEq(c.revokedAt, 0);
        assertEq(c.courseId, COURSE);
        assertEq(c.documentHash, DOC);
    }

    function test_Issue_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit CertificateIssued(1, student, COURSE, issuer, DOC);
        _issue();
    }

    function test_Issue_IdsAreSequential() public {
        vm.startPrank(issuer);
        assertEq(registry.issueCertificate(student, COURSE, DOC), 1);
        assertEq(registry.issueCertificate(student, keccak256("OTHER"), DOC), 2);
        assertEq(registry.issueCertificate(stranger, COURSE, DOC), 3);
        vm.stopPrank();
    }

    function test_Issue_RevertsIfNotIssuer() public {
        bytes32 role = registry.ISSUER_ROLE();
        _unauthorized(stranger, role);
        vm.prank(stranger);
        registry.issueCertificate(student, COURSE, DOC);
    }

    function test_Issue_AdminWithoutIssuerRoleCannotIssue() public {
        bytes32 role = registry.ISSUER_ROLE();
        _unauthorized(admin, role);
        vm.prank(admin);
        registry.issueCertificate(student, COURSE, DOC);
    }

    function test_Issue_RevertsOnZeroStudent() public {
        vm.prank(issuer);
        vm.expectRevert(CertificateRegistry.ZeroAddress.selector);
        registry.issueCertificate(address(0), COURSE, DOC);
    }

    function test_Issue_RevertsOnEmptyHash() public {
        vm.prank(issuer);
        vm.expectRevert(CertificateRegistry.EmptyDocumentHash.selector);
        registry.issueCertificate(student, COURSE, bytes32(0));
    }

    function test_Issue_RevertsOnDuplicateActive() public {
        _issue();
        vm.prank(otherIssuer); // ni otro emisor puede duplicar
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.AlreadyCertified.selector, student, COURSE));
        registry.issueCertificate(student, COURSE, keccak256("otro"));
    }

    function test_Issue_SameStudentDifferentCourseAllowed() public {
        _issue();
        vm.prank(issuer);
        registry.issueCertificate(student, keccak256("OTHER"), DOC);
        assertEq(registry.totalIssued(), 2);
    }

    // ---------- revoke ----------
    function test_Revoke_ByOriginalIssuer() public {
        uint256 id = _issue();
        vm.expectEmit(true, true, false, false);
        emit CertificateRevoked(id, issuer);
        vm.prank(issuer);
        registry.revokeCertificate(id);

        (CertificateRegistry.Certificate memory c, bool valid) = registry.getCertificate(id);
        assertFalse(valid);
        assertGt(c.revokedAt, 0);
        assertEq(c.student, student, "el registro historico se conserva");
    }

    function test_Revoke_ByAdmin() public {
        uint256 id = _issue();
        vm.prank(admin);
        registry.revokeCertificate(id);
        (, bool valid) = registry.getCertificate(id);
        assertFalse(valid);
    }

    function test_Revoke_RevertsForOtherIssuer() public {
        uint256 id = _issue();
        vm.prank(otherIssuer);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.NotAllowedToRevoke.selector, id, otherIssuer));
        registry.revokeCertificate(id);
    }

    function test_Revoke_RevertsForStranger() public {
        uint256 id = _issue();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.NotAllowedToRevoke.selector, id, stranger));
        registry.revokeCertificate(id);
    }

    function test_Revoke_OriginalIssuerLosesPowerWhenRoleRemoved() public {
        uint256 id = _issue();
        bytes32 role = registry.ISSUER_ROLE();
        vm.prank(admin);
        registry.revokeRole(role, issuer);

        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.NotAllowedToRevoke.selector, id, issuer));
        registry.revokeCertificate(id);
    }

    function test_Revoke_RevertsIfNotFound() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.CertificateNotFound.selector, 42));
        registry.revokeCertificate(42);
    }

    function test_Revoke_RevertsIfAlreadyRevoked() public {
        uint256 id = _issue();
        vm.startPrank(admin);
        registry.revokeCertificate(id);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.AlreadyRevoked.selector, id));
        registry.revokeCertificate(id);
        vm.stopPrank();
    }

    function test_Reissue_AfterRevokeAllowed() public {
        uint256 first = _issue();
        vm.prank(admin);
        registry.revokeCertificate(first);

        uint256 second = _issue();
        assertEq(second, 2);
        (, bool firstValid) = registry.getCertificate(first);
        (, bool secondValid) = registry.getCertificate(second);
        assertFalse(firstValid);
        assertTrue(secondValid);
    }

    // ---------- verify / views ----------
    function test_Verify_TrueForValidCertificate() public {
        uint256 id = _issue();
        assertTrue(registry.verify(id, DOC));
    }

    function test_Verify_FalseForWrongHash() public {
        uint256 id = _issue();
        assertFalse(registry.verify(id, keccak256("adulterado")));
    }

    function test_Verify_FalseAfterRevoke() public {
        uint256 id = _issue();
        vm.prank(admin);
        registry.revokeCertificate(id);
        assertFalse(registry.verify(id, DOC));
    }

    function test_Verify_FalseForNonexistent() public view {
        assertFalse(registry.verify(999, DOC));
    }

    function test_GetCertificate_RevertsIfNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.CertificateNotFound.selector, 1));
        registry.getCertificate(1);
    }

    // ---------- fuzz ----------
    function testFuzz_Issue_AnyValidInput(address s, bytes32 course, bytes32 doc) public {
        vm.assume(s != address(0));
        vm.assume(doc != bytes32(0));

        vm.prank(issuer);
        uint256 id = registry.issueCertificate(s, course, doc);

        (CertificateRegistry.Certificate memory c, bool valid) = registry.getCertificate(id);
        assertTrue(valid);
        assertEq(c.student, s);
        assertEq(c.courseId, course);
        assertTrue(registry.verify(id, doc));
    }

    function testFuzz_Issue_OnlyIssuerRoleHolders(address caller) public {
        vm.assume(caller != issuer && caller != otherIssuer);
        bytes32 role = registry.ISSUER_ROLE();
        _unauthorized(caller, role);
        vm.prank(caller);
        registry.issueCertificate(student, COURSE, DOC);
    }

    function testFuzz_Revoke_OnlyAdminOrOriginalIssuer(address caller) public {
        vm.assume(caller != admin && caller != issuer);
        uint256 id = _issue();
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.NotAllowedToRevoke.selector, id, caller));
        registry.revokeCertificate(id);
    }

    function testFuzz_TotalIssuedMatchesCount(uint8 n) public {
        vm.startPrank(issuer);
        for (uint256 i = 0; i < n; i++) {
            registry.issueCertificate(student, bytes32(i), DOC);
        }
        vm.stopPrank();
        assertEq(registry.totalIssued(), n);
    }
}
