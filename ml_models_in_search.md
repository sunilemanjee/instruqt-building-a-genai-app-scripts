> [!NOTE]
> If you would like to watch an instructor walkthrough this challenge, click on the "Challenge Walkthrough" Tab

# Objective
This lab demonstrates how Elasticsearch supports a wide range of machine learning models that can be used during search time to enhance search experiences. You will learn about different model types and use Eland to upload and deploy models to your Elasticsearch cluster for real-time inference during search operations.

ML Models in Elasticsearch Search
===

Elasticsearch supports various machine learning models that can be integrated directly into search workflows for real-time inference. These models enable intelligent search features that go beyond traditional text matching:

**Fill Mask**: Used for query suggestion and auto-completion. When users type partial queries, fill mask models can predict missing words to complete search terms, improving search experience and reducing typos.

**Named Entity Recognition (NER)**: Detects and extracts entities like person names, locations, organizations, and product categories from user queries. This helps understand user intent - for example, detecting if a user is asking for a specific product category or location-based search.

**Question and Answering**: Enables natural language question processing during search. Users can ask complete questions instead of using keywords, and the model extracts the core intent for better search results.

**Sparse Embedding**: Creates high-dimensional sparse vectors for documents and queries, enabling semantic search that understands context and meaning beyond exact keyword matching.

**Text Embedding**: Converts text into dense vector representations for semantic similarity search. This powers features like "find similar documents" and semantic search capabilities.

**Text Classification**: Categorizes user queries or documents into predefined classes. For example, determining if a user query is asking for sales information, support help, or product details, enabling query routing to appropriate search indexes.

**Zero-shot Text Classification**: Automatically categorizes content without training on specific categories. Perfect for auto-labeling documents, dynamic categorization, and handling new product categories without retraining models.

What is Eland
===

Eland is a Python Elasticsearch client and toolkit that bridges the gap between machine learning frameworks and Elasticsearch. It provides utilities for importing pre-trained models from Hugging Face Hub directly into Elasticsearch clusters.

Key capabilities of Eland include:
- Model import from Hugging Face Hub to Elasticsearch ML nodes
- Support for various model formats (PyTorch, TensorFlow, ONNX)
- Automatic model optimization for Elasticsearch inference
- Model deployment and management within Elasticsearch

In this lab, we will use Eland to upload various NLP models to your Elasticsearch cluster, making them available for real-time inference during search operations.

Eland Environment Setup
===

Set environment variables by running the following:

```bash
source ./set-eland-env-variables.sh
```

This script configures the necessary environment variables for connecting to your Elasticsearch cluster and authenticating with the required API keys.

Named Entity Recognition
===

You will upload a Named Entity Recognition model to the Elasticsearch machine learning node via Eland. This model can identify and extract entities like persons, locations, organizations, and miscellaneous entities from text.

Model details: https://huggingface.co/elastic/distilbert-base-cased-finetuned-conll03-english

Run the following command:
```bash
docker run -it --rm --network host \
    docker.elastic.co/eland/eland \
    eland_import_hub_model \
      --url $ES_URL \
      --es-api-key $ES_API_KEY \
      --hub-model-id elastic/distilbert-base-cased-finetuned-conll03-english \
      --task-type ner \
      --start
```

This may take a few minutes to run.

**Search Use Case**: During search, this NER model can analyze user queries to detect if they're looking for specific people, places, or organizations. For example, a query like "hotels near Central Park in New York" would extract "Central Park" as a location and "New York" as another location entity, enabling more precise location-based search.

Text Classification
===

You will upload a text classification model that can detect emotions in text. This model classifies text into emotions like joy, sadness, anger, fear, love, and surprise.

Model details: https://huggingface.co/bhadresh-savani/distilbert-base-uncased-emotion

Run the following command:
```bash
docker run -it --rm --network host \
    docker.elastic.co/eland/eland \
    eland_import_hub_model \
      --url $ES_URL \
      --es-api-key $ES_API_KEY \
      --hub-model-id bhadresh-savani/distilbert-base-uncased-emotion \
      --task-type text_classification \
      --start
```

This may take a few minutes to run.

**Search Use Case**: This model can analyze the emotional tone of user queries to provide more contextually appropriate results. For example, detecting frustration in a support query could prioritize helpful documentation or route to human support agents.

Zero-shot Text Classification
===

You will upload a zero-shot text classification model that can classify text into any categories without being specifically trained on those categories.

Model details: https://huggingface.co/typeform/distilbert-base-uncased-mnli

Run the following command:
```bash
docker run -it --rm --network host \
    docker.elastic.co/eland/eland \
    eland_import_hub_model \
      --url $ES_URL \
      --es-api-key $ES_API_KEY \
      --hub-model-id typeform/distilbert-base-uncased-mnli \
      --task-type zero_shot_classification \
      --start
```

This may take a few minutes to run.

**Search Use Case**: Zero-shot classification enables dynamic query categorization without pre-training. For example, it can automatically determine if a user query is related to "sales", "support", "billing", or "technical questions" and route searches to appropriate knowledge bases or departments. It can also auto-categorize new products or content without manual labeling.

Model Deployment and Testing
===

Once all models are uploaded, they will be available as inference processors in your Elasticsearch cluster. These models can be integrated into:

- **Ingest Pipelines**: For real-time document processing and enrichment
- **Search Pipelines**: For query analysis and enhancement during search
- **Custom Applications**: Via the ML inference API for real-time predictions

The models enable sophisticated search experiences by understanding user intent, extracting meaningful entities, and providing intelligent categorization - all happening in real-time during search operations.

Testing Models in Dev Tools
===

Once the models are deployed, you can test them directly in [Kibana Dev Tools](tab-1) to see how they perform inference.

1. Go to [Kibana Dev Tools](tab-1).

2. Test the **Named Entity Recognition** model:
```json
POST _ml/trained_models/elastic__distilbert-base-cased-finetuned-conll03-english/_infer
{
  "docs": [
    {
      "text_field": "Jimmy who works at Microsoft is looking for a home in Orlando"
    }
  ]
}
```

This will identify entities like "Jimmy" (PERSON), "Microsoft" (ORG), "Orlando" (LOC).

3. Test the **Text Classification** model for emotion detection:
```json
POST _ml/trained_models/bhadresh-savani__distilbert-base-uncased-emotion/_infer
{
  "docs": [
    {
      "text_field": "We found our dream home in Orlando"
    }
  ]
}
```

This will classify the emotional tone of the text (likely "joy" for this example).

4. Test the **Zero-shot Text Classification** model:
```json
POST _ml/trained_models/typeform__distilbert-base-uncased-mnli/_infer
{
  "docs": [
    {
      "text_field": "My smart thermostat keeps disconnecting from WiFi and won't hold temperature settings"
    }
  ],
  "inference_config": {
    "zero_shot_classification": {
      "labels": ["sales", "support", "billing", "technical"]
    }
  }
}
```

This will classify the query into one of the provided labels (likely "support" for this example).

Using Models During Search Time with Ingest Pipelines
===

While ingest pipelines are typically used for document processing, we can use the simulate API to demonstrate real-time inference that could be applied during home search operations.

1. Create a **Zero-shot Classification** pipeline for home inquiry categorization:
```json
PUT _ingest/pipeline/zero-shot-query-classifier
{
  "processors": [
    {
      "inference": {
        "model_id": "typeform__distilbert-base-uncased-mnli",
        "target_field": "classification",
        "field_map": {
          "query_text": "text_field"
        },
        "inference_config": {
          "zero_shot_classification": {
            "labels": ["buying", "renting", "selling"]
          }
        }
      }
    }
  ]
}
```

2. Test the pipeline with a home inquiry:
```json
POST _ingest/pipeline/zero-shot-query-classifier/_simulate
{
  "docs": [
    {
      "_source": {
        "query_text": "what's my home worth in today's market"
      }
    }
  ]
}
```
The model will return "selling" as the most confident label based on the intent to evaluate property value for potential sale.

3. Create a **Named Entity Recognition** pipeline for location extraction:
```json
PUT _ingest/pipeline/ner-location-extractor
{
  "processors": [
    {
      "inference": {
        "model_id": "elastic__distilbert-base-cased-finetuned-conll03-english",
        "target_field": "entities",
        "field_map": {
          "query_text": "text_field"
        }
      }
    }
  ]
}
```

4. Test location extraction from a home search query:
```json
POST _ingest/pipeline/ner-location-extractor/_simulate
{
  "docs": [
    {
      "_source": {
        "query_text": "apartments for rent in downtown Seattle near Pike Place Market"
      }
    }
  ]
}
```
This will extract "Seattle" and "Pike Place Market" as location entities for geographic filtering.

5. Create an **Emotion Classification** pipeline for query sentiment:
```json
PUT _ingest/pipeline/emotion-query-analyzer
{
  "processors": [
    {
      "inference": {
        "model_id": "bhadresh-savani__distilbert-base-uncased-emotion",
        "target_field": "emotion",
        "field_map": {
          "query_text": "text_field"
        }
      }
    }
  ]
}
```

6. Test emotion detection on home search queries:
```json
POST _ingest/pipeline/emotion-query-analyzer/_simulate
{
  "docs": [
    {
      "_source": {
        "query_text": "Our loan was denied the amount we requested"
      }
    }
  ]
}
```
This will detect disappointment or sadness emotions, which could trigger alternative financing suggestions or connect users with lending specialists for revised loan options.

Real-time Search Integration
===

These pipeline simulations demonstrate how ML models can be integrated into search workflows:

**Query Preprocessing**: Before executing a search, analyze the user query to extract entities, detect intent, or classify the request type.

**Dynamic Result Filtering**: Use entity extraction to automatically apply location filters or category restrictions.

**Personalized Responses**: Adjust search result presentation based on detected emotional tone or query classification.

**Smart Routing**: Direct queries to appropriate search indexes or knowledge bases based on zero-shot classification results.

The simulate API shows how these models would perform in real-time during actual search operations, providing intelligent query understanding and enhancement capabilities.