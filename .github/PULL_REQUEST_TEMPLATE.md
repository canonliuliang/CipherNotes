## Summary

- 
- 

## User-facing changes

- 
- 

## Release impact

- Version:
- Release name:
- Download assets updated: pkg / zip / docs / website

## Verification

- [ ] `swift test --scratch-path /tmp/ciphernotes-test`
- [ ] `Packaging/build-release.sh`
- [ ] Website download links point to GitHub Releases latest
- [ ] In-app changelog and README version match `Packaging/release.env`

## Notes

Source pushes update GitHub code and Pages. Public app downloads update only after creating or updating a GitHub Release with the new `pkg` and `zip` assets.
