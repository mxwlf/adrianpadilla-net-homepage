// Values derived at build time rather than hardcoded. The copyright year is
// the only one so far: a static site has no runtime to compute it in, so it is
// fixed when the release is built.
//
// Note that it is fixed at BUILD time, not deploy time. The pipeline builds
// once and promotes that package, so a release cut in December and promoted in
// January still shows the old year until the next release is built. It is also
// the only non-determinism in the build: everything else is content-addressed,
// which is what lets a release be hash-verified on its way to production.
export default {
  year: new Date().getFullYear(),
};
