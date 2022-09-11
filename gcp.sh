# arguments to environment variables
for ARGUMENT in "$@"; do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)

    KEY_LENGTH=${#KEY}
    VALUE="${ARGUMENT:$KEY_LENGTH+1}"

    export "$KEY"="$VALUE"
done

# set google cloud project
gcloud config set project "${PROJECT_ID}"

if [ $1 = "create" ]; then
    gcloud services enable \
        artifactregistry.googleapis.com \
        bigquery.googleapis.com \
        logging.googleapis.com \
        iamcredentials.googleapis.com \
        run.googleapis.com

    # redirect logs to bigquery
    gcloud logging sinks create ${SERVICE} \
        bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${SERVICE} \
        --log-filter='resource.labels.service_name = '"${SERVICE}"' AND jsonPayload.message="Prediction logging"'

    export LOGGER_SA=$(
        gcloud logging sinks describe ${SERVICE} \
            --format='value(writerIdentity)'
    )

    # check if bigquery dataset exists, if not, create
    bq -q show "${SERVICE}" || bq mk --location=${REGION} -d "${SERVICE}"

    bq query --location=${REGION} --nouse_legacy_sql \
        'GRANT `roles/bigquery.dataEditor`
        ON SCHEMA '"${SERVICE}"'
        TO "'${LOGGER_SA}'";'

    # setup workload identity federation
    gcloud iam service-accounts create ${SERVICE} \
        --project "${PROJECT_ID}"

    gcloud iam workload-identity-pools create ${SERVICE} \
        --project="${PROJECT_ID}" \
        --location="global" \
        --display-name=${SERVICE}

    export WORKLOAD_IDENTITY_POOL_ID=$(
        gcloud iam workload-identity-pools describe ${SERVICE} \
            --project="${PROJECT_ID}" \
            --location="global" \
            --format="value(name)"
    )

    gcloud iam workload-identity-pools providers create-oidc ${SERVICE} \
        --project="${PROJECT_ID}" \
        --location="global" \
        --workload-identity-pool=${SERVICE} \
        --display-name=${SERVICE} \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
        --issuer-uri="https://token.actions.githubusercontent.com"

    export WIF_PROVIDER=$(
        gcloud iam workload-identity-pools providers describe ${SERVICE} \
            --project="${PROJECT_ID}" \
            --location="global" \
            --workload-identity-pool=${SERVICE} \
            --format="value(name)"
    )

    gcloud iam service-accounts add-iam-policy-binding "${SERVICE}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --project="${PROJECT_ID}" \
        --role="roles/iam.workloadIdentityUser" \
        --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/${GH_REPO}"

    # provision cloud run requirements
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member=serviceAccount:${SERVICE}@${PROJECT_ID}.iam.gserviceaccount.com \
        --role=roles/run.admin

    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member=serviceAccount:${SERVICE}@${PROJECT_ID}.iam.gserviceaccount.com \
        --role=roles/iam.serviceAccountUser

    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member=serviceAccount:${SERVICE}@${PROJECT_ID}.iam.gserviceaccount.com \
        --role=roles/artifactregistry.repoAdmin

    gcloud artifacts repositories create ${SERVICE} \
        --repository-format=docker \
        --location=${REGION}

    export PROJECT_NR=$(
        gcloud projects list \
            --filter="$(gcloud config get-value project)" \
            --format="value(PROJECT_NUMBER)"
    )

    printf '%s\n' \
        "PROJECT_ID=$PROJECT_ID" \
        "PROJECT_NR=$PROJECT_NR" \
        "SERVICE=$SERVICE" \
        "REGION=$REGION" \
        "SAMPLE_URL_PARAMS=$(<./app/data/sample_url_params.txt)" \
        >.github/workflows/data/.env

    echo "Done!"
fi

if [ $1 = "delete" ]; then
    read -p "Are you sure? (Y/n)" -n 1 -r
    echo # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]; then

        bq rm -r -f -d "${SERVICE}"

        gcloud logging sinks delete ${SERVICE} -q

        gcloud run services delete ${SERVICE} -q \
            --project="${PROJECT_ID}" \
            --region=${REGION}

        gcloud artifacts repositories delete ${SERVICE} -q \
            --project="${PROJECT_ID}" \
            --location=${REGION}

        gcloud iam workload-identity-pools providers delete ${SERVICE} -q \
            --project="${PROJECT_ID}" \
            --location="global" \
            --workload-identity-pool=${SERVICE}

        gcloud iam workload-identity-pools delete ${SERVICE} -q \
            --project="${PROJECT_ID}" \
            --location="global"

        gcloud iam service-accounts delete "${SERVICE}@${PROJECT_ID}.iam.gserviceaccount.com" -q \
            --project "${PROJECT_ID}"

        echo "Done!"

    fi
fi
