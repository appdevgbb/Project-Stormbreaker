import axios from "axios";
import * as React from 'react';
import { CrudTable, Spinner } from "./components";

export default function CreateNewJob() {
  const [open, setOpen] = React.useState(true);
  const [isLoading, setIsLoading] = React.useState(true);
  const [data, setData] = React.useState([]);

  const host = process.env.REACT_APP_STORMBREAKER_API_HOST || "localhost";
  const port = process.env.REACT_APP_STORMBREAKER_API_PORT || "8000";
  const crud_url = `http://${host}:${port}/api/jobs/`;

  const [validationErrors, setValidationErrors] = React.useState({});
  const options_available = ["Guam", "Katrina", "Gustav"];

  const fetchData = async () => {
    setIsLoading(true);
    try {
      const response = await axios.get(crud_url);
      setData(response.data);
      setIsLoading(false);
      console.log(response.data);
    } catch (error) {
      console.log(error);
      setIsLoading(false);
    }
  };

  React.useEffect(() => {
    fetchData();
  }, []);

  /* Column Headers */
  const columns = React.useMemo(
    () => [
      {
        accessorKey: "customer",
        header: "Customer",
        muiEditTextFieldProps: {
          required: true,
          error: !!validationErrors?.customer,
          helperText: validationErrors?.customer,
          onFocus: () =>
            setValidationErrors({
              ...validationErrors,
              customer: undefined,
            }),
        },
      },
      {
        accessorKey: "simulation",
        header: "Simulation",
        editVariant: "select",
        editSelectOptions: options_available,
        muiEditTextFieldProps: {
          select: true,
          error: !!validationErrors?.simulation,
          helperText: validationErrors?.simulation,
        },
      },

      {
        accessorKey: "np",
        header: "NP",
        muiEditTextFieldProps: {
          required: true,
          error: !!validationErrors?.np,
          helperText: validationErrors?.np,
          onFocus: () =>
            setValidationErrors({
              ...validationErrors,
              np: undefined,
            }),
        },
      },

      {
        accessorKey: "slots",
        header: "Slots",
        muiEditTextFieldProps: {
          required: true,
          error: !!validationErrors?.slots,
          helperText: validationErrors?.slots,
          onFocus: () =>
            setValidationErrors({
              ...validationErrors,
              slots: undefined,
            }),
        },
      },
    ],
    [validationErrors]
  );

  // Validators
  const validateLength = (value, field, lowest) => {
    if (value.length === 0) {
      return `${field} cannot be empty`;
    } else if (value.length < lowest) {
      return `A minimum of ${lowest} Characters is required`;
    } else {
      return "";
    }
  };

  const validateSelect = (value, options) => {
    return options.includes(value);
  };

  const validateMinNumber = (value, minimum) => {
    return value > minimum;
  };

  function validateData(data) {
    return {
      name: validateLength(data.customer, "Customer", 1),
      simulation: !validateSelect(data.simulation, options_available)
        ? "Option Unavailable"
        : "",
      np: !validateMinNumber(data.np, 0)
        ? "NP cannot be less than 0"
        : "",
      slots: !validateMinNumber(data.slots, 0)
        ? "Number of slots cannot be less than 0"
        : "",
    };
  }



  return (
    <React.Fragment>
      <CrudTable
        data={data}
        fetchData={fetchData}
        setValidationErrors={setValidationErrors}
        columns={columns}
        crud_url={crud_url}
        validateData={validateData}
      />
    </React.Fragment>
  );
}