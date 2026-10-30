// Values derived at build time rather than hardcoded. The copyright year is
// the only one so far: a static site has no runtime to compute it in, so it is
// fixed at build and refreshed by the next deploy.
export default {
  year: new Date().getFullYear(),
};
