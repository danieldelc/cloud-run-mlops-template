import json
import os

import joblib
import pandas as pd
from fastapi import Depends, FastAPI

from .data.pydantic_model import PredictModel
from .funs import (
    get_bigquery_predict_logs,
    input_vars,
    load_test_data,
    output_var,
    univariate_drift,
)

app = FastAPI()


@app.get("/version")
async def version():
    """Returns the current service image name"""
    return {"image": os.getenv("IMAGE", "Local Image")}


@app.get("/monitor")
async def monitor():
    """Returns the analysis of the ML model inference"""
    baseline_records = load_test_data()
    if os.getenv("K_REVISION"):
        records = get_bigquery_predict_logs(
            os.getenv("PROJECT_ID"),
            os.getenv("K_SERVICE"),
            os.getenv("K_REVISION"),
            input_vars,
            output_var,
            10000,
        )
    else:
        records = baseline_records
    return {
        "univariate_drift": univariate_drift(
            baseline_records, records, input_vars
        ),
        "revision_name": os.getenv("K_REVISION", "local"),
    }


@app.post("/predict")
async def predict(params: PredictModel = Depends()):
    mlmodel = joblib.load("./app/data/ml_model.joblib")
    prediction_input = pd.DataFrame(dict(params), index=[0])
    prediction = mlmodel.predict(prediction_input)[0]
    # log for monitoring
    print(
        json.dumps(
            {
                "severity": "INFO",
                "message": "Prediction logging",
                "variables": {**dict(params), **{output_var: prediction}},
            }
        )
    )
    return {"prediction": prediction}
