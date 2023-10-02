import React from "react";
import clsx from "clsx";
import styles from "./styles.module.css";

const FeatureList = [
  {
    title: "Easy to Learn",
    Svg: require("@site/static/img/learn.svg").default,
    description: (
      <>
        These tutorials have background for each step so you know what is
        happening and why it's there.
      </>
    ),
  },
  {
    title: "Easy to Build",
    Svg: require("@site/static/img/build.svg").default,
    description: (
      <>
        The environment you'll build is modular and can be easily adapted to a
        variety of hardware- all leading to the same platform.
      </>
    ),
  },
  {
    title: "Easy to Share",
    Svg: require("@site/static/img/share.svg").default,
    description: <>Easily share the platform you build with others.</>,
  },
];

function Feature({ Svg, title, description }) {
  return (
    <div className={clsx("col col--4")}>
      <div className="text--center">
        <Svg className={styles.featureSvg} role="img" />
      </div>
      <div className="text--center padding-horiz--md">
        <h3>{title}</h3>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
