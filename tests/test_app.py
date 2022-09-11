import os

import pytest
from fastapi.testclient import TestClient
from numpy.testing import assert_almost_equal

from app.main import app, input_vars, load_test_data, univariate_drift

client = TestClient(app)


def test_version():
    response = client.get("/version")
    assert response.status_code == 200
    assert response.json() == {"image": os.getenv("IMAGE", "Local Image")}


def test_monitor():
    baseline_records = load_test_data()
    response = client.get("/monitor")
    assert response.status_code == 200
    assert response.json() == {
        "univariate_drift": univariate_drift(
            baseline_records, baseline_records, input_vars
        ),
        "revision_name": "local",
    }


@pytest.mark.parametrize(
    argnames="scenario",
    argvalues=list(load_test_data(10)),
)
def test_predict(scenario):
    response = client.post("/predict", params=scenario)
    assert response.status_code == 200
    assert_almost_equal(response.json()["prediction"], scenario["y_pred"])
