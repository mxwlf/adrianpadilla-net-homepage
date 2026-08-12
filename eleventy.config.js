export default function (eleventyConfig) {
  // Passthrough copy for static assets
  eleventyConfig.addPassthroughCopy("src/assets");
  eleventyConfig.addPassthroughCopy("src/static");

  // SWA reads its config from the root of output_location, not the repo root.
  eleventyConfig.addPassthroughCopy({
    "staticwebapp.config.json": "staticwebapp.config.json",
  });

  return {
    dir: {
      input: "src",
      output: "dist",
      includes: "_includes",
      data: "_data",
    },
    templateFormats: ["njk", "md", "html"],
    htmlTemplateEngine: "njk",
    markdownTemplateEngine: "njk",
  };
}
