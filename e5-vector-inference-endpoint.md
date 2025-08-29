
# Objectives:
- Learn about and create inference API
  - This will automatically deploy E5-small with the configured settings
  - This will then allow us to generate embeddings for our uploaded text and queries

# e5

Early embedding models used English-only datasets, leading to language-specific models for German, French, Chinese, etc. that only worked within their respective languages. Multilingual embedding models solve this by training on aligned datasets with similar sentences across languages, learning semantic relationships rather than translations and embedding multiple languages into the same mathematical space. This creates truly cross-lingual models that can work with text pairs in any of their trained languages, representing concepts in a language-agnostic way where semantically similar content clusters together regardless of language.

# Steps

View e5 Endpoint
===

1. Open the [button label="Kibana - Inference Endpoints"](tab-0) tab.

2. Notice an e5 model has been preconfigured. You will use this model in the next steps.
![Aug-07-2025_at_10.32.25-image.png](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/02aa3c64195fe25b750a2a2974e36f44/assets/Aug-07-2025_at_10.32.25-image.png)

Create the Endpoint
===

1. Open the [button label="Kibana - Dev Tools"](tab-1) tab. If you accidentally navigated away, click on the menu button in the upper left.

![Screenshot 2025-08-13 at 3.08.20 PM.png](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/a35ce778df802c8f9e1fede15f4329d2/assets/Screenshot%202025-08-13%20at%203.08.20%E2%80%AFPM.png)

2. Then click select `Developer Tools`

![Screenshot 2025-08-13 at 3.13.48 PM.png](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/d88049bd9d02f9ff470e5b904f1e456f/assets/Screenshot%202025-08-13%20at%203.13.48%E2%80%AFPM.png)

3. Clear out any existing text examples within the Dev Tools window by clicking on `Clear this input`.

4. Paste the code below into the console:
```
PUT _inference/text_embedding/my-e5-endpoint
{
  "service": "elasticsearch",
  "service_settings": {
    "num_allocations": 4,
    "num_threads": 1,
    "model_id": ".multilingual-e5-small_linux-x86_64"
  },
  "chunking_settings": {
    "strategy": "sentence",
    "max_chunk_size": 100,
    "sentence_overlap": 1
  }
}
```

> [!NOTE]
> If you observe the following error:
> {
>   "statusCode": 502,
>   "error": "Bad Gateway",
>   "message": "Client request timeout for: https://xxxxxx with request PUT /_inference/xxxx"
> }
> The model is deploying but timed out. Wait a few minutes for the model allocators to deploy and proceed to next step.

5. Run the code and ensure there are no errors.

6. Run the below code to verify the endpoint was created:
```
GET _inference/my-e5-endpoint
```

Test Generating e5 embeddings
===

1. Navigate back to the Console.
   - Open the [button label="Kibana - Dev Tools"](tab-1) tab.

2. Run the following code in the Console:
```
POST _inference/my-e5-endpoint
{
  "input": "There is no reason anyone would want a computer in their home"
}
```

You should see a response with dense embeddings comprised of an array of numerical values.
The output should look like:
```nocopy
{
  "text_embedding": [
    {
      "embedding": [
        0.011442271,
        -0.06755284,
        -0.02892523,
        -0.034972776,
        0.071749955,
        0.021751532,
        0.04523666,
        -0.002443524,
        0.073736876,
        ....
      ]
    }
  ]
}
```


Third-Party Embedding Services
===

ELSER and E5 models come out of the box. However, you may choose to use GCP, AWS, Azure, Cohere, or other services instead of the models provided OOTB. Here are examples of how to create inference endpoints to third-party services. Elasticsearch will call those services during ingest and search time to automatically inference and chunk your datasets.

**AWS Bedrock:**
```
PUT _inference/text_embedding/amazon_bedrock_embeddings
{
  "service": "amazonbedrock",
  "service_settings": {
    "access_key": "AWS-access-key",
    "secret_key": "AWS-secret-key",
    "region": "us-east-1",
    "provider": "amazontitan",
    "model": "amazon.titan-embed-text-v2:0"
  }
}
```

**Azure OpenAI:**
```
PUT _inference/text_embedding/azure_openai_embeddings
{
  "service": "azureopenai",
  "service_settings": {
    "api_key": "Azure-API-key",
    "resource_name": "resource-name",
    "deployment_id": "deployment-id",
    "api_version": "2024-02-01"
  }
}
```

**GCP Vertex AI:**
```
PUT _inference/text_embedding/google_vertex_ai_embeddings
{
  "service": "googlevertexai",
  "service_settings": {
    "service_account_json": "service-account-json",
    "model_id": "model-id",
    "location": "location",
    "project_id": "project-id"
  }
}
```

**Cohere:**
```
PUT _inference/text_embedding/cohere_embeddings
{
  "service": "cohere",
  "service_settings": {
    "api_key": "Cohere-API-key",
    "model_id": "embed-english-light-v3.0",
    "embedding_type": "byte"
  }
}
```