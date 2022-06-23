// @ts-check
// Note: type annotations allow type checking and IDEs autocompletion

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: "We have tutorials",
  tagline: "and tutorial accessories",
  url: "https://suchcodewow.io",
  baseUrl: "/",
  onBrokenLinks: "throw",
  onBrokenMarkdownLinks: "warn",
  favicon: "img/favicon.ico",
  organizationName: "suchcodewow", // Usually your GitHub org/user name.
  projectName: "scw", // Usually your repo name.

  plugins: [
    async function myPlugin(context, options) {
      return {
        name: "docusaurus-tailwindcss",
        configurePostCss(postcssOptions) {
          // Appends TailwindCSS and AutoPrefixer.
          postcssOptions.plugins.push(require("tailwindcss"));
          postcssOptions.plugins.push(require("autoprefixer"));
          return postcssOptions;
        },
      };
    },
  ],

  presets: [
    [
      "classic",
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          breadcrumbs: false,
          sidebarPath: require.resolve("./sidebars.js"),
          // Please change this to your repo.
          //editUrl: "https://github.com/suchcodewow/scw/",
        },

        theme: {
          customCss: require.resolve("./src/css/custom.css"),
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      image: "img/love_code.jpg",
      autoCollapseSidebarCategories: true,
      navbar: {
        title: "SuchCodeWow",
        logo: {
          alt: "SuchCodeWow Logo",
          src: "img/wow.png",
        },
        items: [
          {
            type: "dropdown",
            label: "Tutorials",
            position: "left",
            items: [
              {
                type: "doc",
                docId: "intro",
                label: "Welcome",
              },
              {
                type: "doc",
                docId: "k8s/index",
                label: "Modular: Kubernetes",
              },
              {
                type: "doc",
                docId: "accelerator-azure/index",
                label: "Accelerator: Azure",
              },
            ],
          },
          {
            type: "dropdown",
            label: "Helpers",
            position: "left",
            items: [
              {
                type: "doc",
                docId: "scripts/index",
                label: "Welcome",
              },
              {
                type: "doc",
                docId: "scripts/webapp",
                label: "Azure Web Apps",
              },
            ],
          },
          {
            href: "https://github.com/suchcodewow/scw",
            label: "GitHub",
            position: "right",
          },
        ],
      },
      footer: {
        style: "dark",
        copyright: `Copyright © ${new Date().getFullYear()} SuchCodeWow`,
      },
      prism: {
        theme: require("prism-react-renderer/themes/dracula"),
        darkTheme: require("prism-react-renderer/themes/dracula"),
      },
    }),
};

module.exports = config;
