
# Objectives:
Elasticsearch provides the inference API to enable data vectorization. The inference APIs allow you to create inference endpoints and integrate with various machine learning models, including built-in models (ELSER, E5), models uploaded via Eland, and third-party services such as Amazon Bedrock, Anthropic, Azure AI Studio, Cohere, Google AI, Mistral, OpenAI, and Hugging Face.

- Learn about ELSER EIS API
- GPU backed inference endpoint

# ELSER

ELSER is Elastic's AI search model built on BERT that requires no ML expertise and deploys with a few clicks. It repurposes BERT's masked language modeling head to create sparse vectors by generating probability distributions over vocabulary words for each query term, with each vector value representing how much each vocabulary word is activated by the input query.

![Jul-19-2025_at_10.42.21-image.png](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/9c1b0e2b897f783b7a4d46377af16724/assets/Jul-19-2025_at_10.42.21-image.png)

ELSER creates sparse vectors where only a small fraction of vocabulary dimensions are activated, enabling "text expansion" that finds semantically relevant documents even when they don't contain the exact query terms. This solves the vocabulary mismatch problem by expanding queries to include related words - for example, "blues band played songs" might activate terms like "album," "artist," "concert," and "jazz" to surface more relevant results.

![Jul-19-2025_at_10.44.09-image.png](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/0999ad67ea3e24e76a72843d1ad27634/assets/Jul-19-2025_at_10.44.09-image.png)

ELSER's text expansion creates a granular "relevance continuum" that's more powerful than synonyms and is more resource-efficient than dense vectors due to its sparse nature.

Want to learn more? https://ela.st/more-about-elser

# Steps

View ELSER Endpoints
===

1. Open the [button label="Kibana - Inference Endpoints"](tab-0) tab.

2. Notice an ELSER endpoint has been preconfigured. This model runs on ML nodes leveraging CPUs

![Jul-19-2025_at_15.49.28-image.png](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/57caace0f13644ab1bd7102c38b34f86/assets/Jul-19-2025_at_15.49.28-image.png)

3.  This is the GPU backed ELSER endpoint. This endpoint will be used in the with the properties index to speed up ingestion and search
![Aug-04-2025_at_16.32.41-image.png](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/af0a6ec4673fb284bf7f66cc1d60aecb/assets/Aug-04-2025_at_16.32.41-image.png)


Test Generating ELSER embeddings
===

1. Navigate back to the Console.
   - `Upper Left Menu > Dev Tools`

2. Run the following against the GPU back ELSER endpoint
```
POST _inference/.elser-2-elastic
{
  "input": "There is no reason anyone would want a computer in their home"
}
```
You should see a response with sparse embeddings comprised of an array of tokens and weights. The output should look like:
```
{
  "sparse_embedding": [
    {
      "is_truncated": false,
      "embedding": {
        "a": 0.17132168,
        "advantage": 0.6308771,
        "alien": 0.09799217,
        "alternative": 0.1301319,
        "apartment": 0.70565426,
        "apple": 0.2690888,
        "availability": 0.21323632,
        "available": 0.16618185,
        "building": 0.08674725,
        "buy": 0.9236794,
        "buying": 0.11472927,
        "cheap": 0.3341684,
        "comfort": 0.02095185,
        "commercial": 0.455078,
        "computer": 2.6800375,
        "computers": 1.998455,
        "computing": 0.52651703,
```