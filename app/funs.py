import json

from google.cloud import bigquery
from scipy.stats import ks_2samp

from .data.pydantic_model import PredictModel


def load_test_data(n_records: int = None) -> list:
    """Gets the test data records"""
    with open("./app/data/test_data.json", "r") as read_file:
        test_records = json.load(read_file)
    return test_records[:n_records]


def get_target_var(input_vars: list) -> str:
    """Gets the target variable name from the first test record"""
    all_vars = list(load_test_data(1)[0])
    non_target = input_vars + ["y_pred"]
    target = list(set(all_vars) - set(non_target))[0]
    return target


def get_bigquery_predict_logs(
    project_id: str,
    k_service: str,
    k_revision: str,
    input_vars: list,
    output_var: str,
    last_n_rows: int,
) -> list:
    """Gets last n records from the prediction logs sinked into bigquery and
    tranform them into a list of records
    """
    query = """
        SELECT
            {}
        FROM
            `{}.{}.*`
        WHERE
            resource.labels.revision_name = '''{}'''
        ORDER BY timestamp DESC
        LIMIT {}
    """.format(
        ",".join(
            ["jsonPayload.variables." + s for s in input_vars + [output_var]]
        ),
        project_id,
        k_service,
        k_revision,
        last_n_rows,
    )
    client = bigquery.Client()
    records = [i for i in client.query(query)]
    return records


def univariate_drift(
    baseline_data: list, test_data: list, input_vars: list
) -> dict:
    """Gets two samples of data and calculates univariate data drift using KS
    test
    """
    drift = {}
    for var in input_vars:
        baseline = [d[var] for d in baseline_data]
        test = [d[var] for d in test_data]
        drift[var] = {
            "kstest_pval": ks_2samp(baseline, test)[1] if len(test) > 0 else 0,
            "baseline_samples": len(baseline),
            "test_samples": len(test),
        }
    return drift


input_vars = [*PredictModel.__annotations__]

output_var = get_target_var(input_vars)
