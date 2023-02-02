import React from "react";
import { useEffect } from "react";
import clsx from "clsx";
import Layout from "@theme/Layout";
import Link from "@docusaurus/Link";
import useDocusaurusContext from "@docusaurus/useDocusaurusContext";
import styles from "./index.module.css";
import HomepageFeatures from "@site/src/components/HomepageFeatures";

export default function Home() {
  const { siteConfig } = useDocusaurusContext();
  useEffect(() => {
    const initTerminal = async () => {
      const { Terminal } = await import("xterm");
      const term = new Terminal();
      term.open(document.getElementById("xterm-container"));
      term.write("Hello from \x1B[1;3;31mxterm.js\x1B[0m $ ");
    };
  }, []);

  return (
    <Layout title={` ${siteConfig.title}`} description="Description will go into a meta tag in <head />">
      {/* <HomepageHeader /> */}
      <div id="xterm-container" style={{ height: 500, width: 500, border: 1 }}></div>
      <main>{/* <HomepageFeatures /> */}</main>
    </Layout>
  );
}
