# TODO

## Next Session Tasks

### 1. Add GitHub Workflow Trigger Command ✅ COMPLETED
- [x] Add a `just run-workflow` command that triggers the GitHub Actions workflow
- [x] Should use `gh workflow run build.yaml` 
- [x] Consider adding workflow status checking command as well (`just workflow-status`)
- [x] Update README with the new command

### 2. Analyze Custom CoreOS Integration ✅ COMPLETED
- [x] Study the commented-out Stage 3 in `../custom-coreos/Containerfile` (lines 77-92)
- [x] Understand how ZFS RPMs were previously installed with `rpm-ostree install`
- [x] Design new approach using the RPM container instead of building from source
- [x] Create example showing how to:
  - Pull the fedora-zfs-kmods container 
  - Extract/mount RPMs during bootc build
  - Install with rpm-ostree in the NAS OS build
- [x] Update README with usage examples for bootc integration

### 3. Update CLAUDE.md ✅ COMPLETED
- [x] Reflect current project state after all recent changes
- [x] Update architecture description with:
  - New compatibility checking system
  - GitHub workflow structure (2-job design)
  - Justfile command structure
  - Container registry publishing
- [x] Add information about the relationship to custom-coreos project
- [x] Update common development commands section

## Future Improvements (Backlog)

### Workflow Enhancements ✅ MOSTLY COMPLETED
- [x] Add automated/scheduled builds with caching system:
  - [x] Nightly scheduled workflow (`schedule: cron: '0 6 * * *'`)
  - [x] Check if build already exists for current ZFS+kernel combo
  - [x] Exit early if container already published for this version
  - [x] Only build if new ZFS version or kernel version detected
  - [x] Use GitHub Container Registry API to check existing images
  - [x] Enhanced with attestation verification for build integrity
  - [x] Force rebuild option for manual overrides
- [ ] Add workflow to clean up old container images
- [ ] Consider matrix builds for multiple kernel versions if needed
- [ ] Consider adding automated builds on CoreOS stable image updates

### Local Development
- [ ] Add command to test RPM installation locally
- [ ] Consider adding integration test that verifies RPMs work in bootc context
- [ ] Add command to compare local vs published container contents

### Documentation
- [ ] Add troubleshooting section for common ZFS module loading issues
- [ ] Document performance impact of splitting ZFS build from NAS OS build
- [ ] Add examples for different bootc use cases beyond NAS

## Notes from Current Session

✅ **Working as of today:**
- GitHub Actions workflow successfully creates artifacts and attestations
- Compatibility checking prevents incompatible builds
- Local development workflow with Justfile commands
- Container images published to GHCR with proper tagging

📝 **Key insights:**
- Splitting ZFS kmod build saves ~10 minutes on daily NAS OS builds
- Previous approach built ZFS from source in every NAS OS build
- New approach pre-builds and caches ZFS RPMs in containers
- Need to bridge from container RPMs to rpm-ostree installation