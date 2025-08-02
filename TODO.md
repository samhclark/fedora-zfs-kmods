# TODO

## Project Status: ✅ COMPLETE

This fedora-zfs-kmods project is functionally complete and ready for production use.

### ✅ Core Functionality Implemented
- **Automated ZFS kmod builds**: Nightly scheduled workflow with version detection
- **Container image cleanup**: Weekly cleanup with attestation preservation  
- **Compatibility checking**: Prevents incompatible ZFS/kernel combinations
- **Local development**: Full Justfile command suite for testing and workflow management
- **Container registry**: Automated publishing to GHCR with proper tagging and attestations
- **Custom CoreOS integration**: Complete bootc examples and RPM extraction patterns

### ✅ Safety & Reliability 
- **Build verification**: Attestation checking and force rebuild options
- **Cleanup safety**: Minimum version protection with early validation
- **Error handling**: Graceful failures with clear diagnostics
- **Local testing**: `just cleanup-dry-run` and other validation commands

## Optional Future Enhancements

### Local Development (Nice to Have)
- [ ] Add `just test-rpms` command to verify RPM installation locally
- [ ] Add troubleshooting section for ZFS module loading issues

### Code Quality & Maintainability
- [ ] **Refactor complex Justfile bash into Python scripts**: The `cleanup-dry-run` command and version checking logic have grown complex with hairy bash/jq combinations. Consider rewriting core components as self-contained Python scripts using `uv` and inline script dependencies (PEP 723). This would:
  - Allow sharing identical logic between Justfile commands and GitHub workflows
  - Improve readability and maintainability of complex JSON parsing and API logic
  - Keep simple operations (like `gh` CLI piping) as bash for simplicity
  - Enable better error handling and testing of core logic

### Workflow (Won't Fix - Not Needed for Single-User NAS)
- ~~Matrix builds for multiple architectures~~ (x86_64 only)
- ~~Automated builds on CoreOS updates~~ (manual is sufficient)  
- ~~Integration tests in bootc context~~ (too complex for benefit)

## Next Steps

**This repository is complete.** Focus should shift to:
1. **custom-coreos repository**: Implement the ZFS RPM integration patterns documented here
2. **NAS deployment**: Use the pre-built containers in production bootc builds

## Key Artifacts for Integration

- **Container images**: `ghcr.io/samhclark/fedora-zfs-kmods:zfs-{version}_kernel-{version}`
- **Integration examples**: See README.md bootc integration section
- **Local testing**: `just versions`, `just check-compatibility`, `just cleanup-dry-run`