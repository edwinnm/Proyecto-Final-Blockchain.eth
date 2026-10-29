import { parseAbi, createPublicClient, http } from 'viem'
import { foundry } from 'viem/chains'

export const CONTRACT_ADDRESS = import.meta.env.VITE_CONTRACT_ADDRESS
export const RPC_URL = import.meta.env.VITE_RPC_URL ?? 'http://127.0.0.1:8545'

// ABI mínima (human-readable); incluye los errores para poder decodificar reverts.
export const abi = parseAbi([
  'function ISSUER_ROLE() view returns (bytes32)',
  'function DEFAULT_ADMIN_ROLE() view returns (bytes32)',
  'function hasRole(bytes32 role, address account) view returns (bool)',
  'function grantRole(bytes32 role, address account)',
  'function revokeRole(bytes32 role, address account)',
  'function totalIssued() view returns (uint256)',
  'function issueCertificate(address student, bytes32 courseId, bytes32 documentHash) returns (uint256 id)',
  'function revokeCertificate(uint256 id)',
  'function getCertificate(uint256 id) view returns ((address student, address issuer, uint64 issuedAt, uint64 revokedAt, bytes32 courseId, bytes32 documentHash) cert, bool valid)',
  'function verify(uint256 id, bytes32 documentHash) view returns (bool)',
  'event CertificateIssued(uint256 indexed id, address indexed student, bytes32 indexed courseId, address issuer, bytes32 documentHash)',
  'event CertificateRevoked(uint256 indexed id, address indexed revokedBy)',
  'error ZeroAddress()',
  'error EmptyDocumentHash()',
  'error AlreadyCertified(address student, bytes32 courseId)',
  'error CertificateNotFound(uint256 id)',
  'error AlreadyRevoked(uint256 id)',
  'error NotAllowedToRevoke(uint256 id, address caller)',
  'error AccessControlUnauthorizedAccount(address account, bytes32 neededRole)',
])

// Lectura sin wallet: cualquiera puede verificar un certificado.
export const publicClient = createPublicClient({ chain: foundry, transport: http(RPC_URL) })
