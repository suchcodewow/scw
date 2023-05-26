import React from "react";
import NotFound from "@theme-original/NotFound";
import { BrowserRouter as Router, Switch, Route, Redirect } from "react-router-dom";

export default function NotFoundWrapper(props) {
  return (
    <>
      <Redirect to="/" />
    </>
  );
}
