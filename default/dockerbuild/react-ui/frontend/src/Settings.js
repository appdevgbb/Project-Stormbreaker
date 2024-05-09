import * as React from "react";
import { Typography } from "@mui/material";

function preventDefault(event) {
  event.preventDefault();
}

export default function Settings() {
  return (
    <React.Fragment>
      <Typography
        component="h1"
        variant="h6"
        color="inherit"
        noWrap
        sx={{ flexGrow: 1 }}
      >
        Settings
      </Typography>
    </React.Fragment>
  );
}
