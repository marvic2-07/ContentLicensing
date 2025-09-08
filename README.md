ContentLicensing Smart Contract

A **Media Licensing Marketplace** built with [Clarity](https://docs.stacks.co/docs/clarity/overview), enabling creators to register digital media, sell licenses, and enforce royalties on resales.  

This contract ensures **fair compensation for creators** while supporting a **secondary marketplace** for media rights.

Features
 **Register Media**  
  Creators can register media with metadata, base price, and royalty percentage (bps).

 **Buy Licenses**  
  Buyers purchase licenses directly from creators (on-chain minting).

**Resale Marketplace**  
  License owners can list and resell their licenses.
 **Royalty Enforcement**  
  Royalties are automatically split and paid to creators on resale.
**Transfer & Gift**  
  Licenses can be transferred between principals.
 **Revocation**  
  Creators can revoke issued licenses if needed.

 **Read-Only Views**  
  Query registered media, issued licenses, listings, and counters.

Contract Structure

- **Media Registry** – stores creator, title, rights, price, and royalties.  
- **Licenses** – represents ownership of purchased media licenses.  
- **Listings** – allows licenses to be listed for resale.  
- **Helpers** – validates ownership, royalties, and safe STX transfers.

Error Codes

| Code | Meaning              |
|------|----------------------|
| `u100` | Unauthorized action |
| `u101` | Item not found       |
| `u102` | Invalid input        |
| `u103` | Zero price error     |
| `u104` | Already listed       |
| `u105` | Not listed           |
| `u106` | Not owner            |
| `u107` | Transfer failed      |
Usage

 1. Register Media
```clarity
(contract-call? .ContentLicensing register-media "Song A" "All rights reserved" u1000 u500)
