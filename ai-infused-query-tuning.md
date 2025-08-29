
## Objective

This lab provides hands-on experience with Elastic retrievers and semantic reranking capabilities. You will explore multilingual search with E5 embeddings, compare different retrieval methods using RRF (Reciprocal Rank Fusion), implement semantic reranking for improved relevance, and use AI-infused tuning to optimize search results. You can explore the UI independently or follow the guided [Challenge Walkthrough](tab-1) for a structured demonstration.

Multi Language (e5)
===

### About E5 Multilingual Model

The E5 multilingual embedding model enables cross-language search capabilities. Users can query data in one language while the source content is in another. For example, you can search English-indexed data using French queries.

**Supported Languages:** Visit [Elastic's multilingual-e5-small-optimized model](https://huggingface.co/elastic/multilingual-e5-small-optimized) and check the "# languages" section to see all supported languages.

### Exercise: Testing Cross-Language Search
![Adobe Express - 2025-08-12_11-15-38.gif](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/a1a2ae126e5520663b66c5e21b867c2a/assets/Adobe%20Express%20-%202025-08-12_11-15-38.gif)


1. **Configure Search Settings**
   - Set **E5 Semantic Search** weight to `3.0` or higher under `Search Settings, Field Boosts`
   - Configure **Location Filter**:
     - Latitude: `41.9172`
     - Longitude: `-87.6270`

2. **Test English Query**
   Run the following English query:
   ```
   House with direct beach access and nature walks
   ```
   **Expected Result:** The top 3 results should include `728 W JACKSON Boulevard #313, Chicago, IL 60661` & `211 N Harbor Drive #1501, Chicago, IL 60601`


Optional - Test Multiple Language Translations
===


1. **Test French Translation**
   Run the French equivalent of the same query:
   ```
   Maison avec accès direct à la plage et balades en pleine nature
   ```

2. **Test Hindi Translation**
   ```
   समुद्र तट तक सीधी पहुंच और प्रकृति भ्रमण के साथ घर
   ```

3. **Test German Translation**
   ```
   Haus mit direktem Strandzugang und Naturwanderwegen
   ```

4. **Test Italian Translation**
   ```
   Casa con accesso diretto alla spiaggia e sentieri naturalistici
   ```

5. **Test Japanese Translation**
   ```
   ビーチへの直接アクセスと自然散歩ができる家
   ```

6. **Test Simplified Chinese Translation**
   ```
   直通海滩和自然步道的房子
   ```

7. **Test Traditional Chinese Translation**
    ```
    直通海灘和自然步道的房子
    ```

**Expected Result for All Language Tests:** The properties `728 W JACKSON Boulevard #313, Chicago, IL 60661` and `211 N Harbor Drive #1501, Chicago, IL 60601` should appear within the top 3 results for each language query, demonstrating effective multilingual search capabilities.

RRF
===

### Understanding RRF

RRF combines results from multiple search methods to improve overall search quality. It's particularly effective for hybrid search scenarios where different retrieval methods return complementary results.

### When to Use RRF

**✅ Use RRF when:**
- Combining multiple search methods (ELSER + Text Match + E5 Semantic Search)
- Different search methods return overlapping but distinct results
- You want to balance strengths of different retrieval approaches

**❌ Don't use RRF when:**
- Using only one search method
- All search methods return identical results
- No meaningful overlap between retrieval methods

### Exercise: Comparing Individual Search Methods vs RRF

1. **Test with E5 Only**
  ![Adobe Express - 2025-08-12_14-46-26.gif](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/672341442af0bd21bbb91b48e1d18c55/assets/Adobe%20Express%20-%202025-08-12_14-46-26.gif)
	- Click **Reset All Boost to 0** under `Match Fields`
   - Configure **Location Filter**:
     - Latitude: `41.9172`
     - Longitude: `-87.6270`
   - Select **Body Content E5** under `Match Fields`
   - Unselect all other fields
   - Run the query:
   ```
   Amazing lake view with an updated kitchen and a open floor plan
   ```
   **Observation:** Note the position of `3534 N LAKE SHORE Drive #12C, Chicago, IL 60657` in the results.

3. **Test with ELSER Only**
   ![Adobe Express - 2025-08-12_14-48-22.gif](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/25d2ab2223e7b36eace4e88d16084b08/assets/Adobe%20Express%20-%202025-08-12_14-48-22.gif)
   - Click **Reset All Boost to 0** under `Match Fields`
   - Configure **Location Filter**:
     - Latitude: `41.9172`
     - Longitude: `-87.6270`
   - Select **Body Content ELSER** under `Match Fields`
   - Unselect all other fields
   - Run the same query
   ```
   Amazing lake view with an updated kitchen and a open floor plan
   ```
   **Observation:** Note where `3534 N LAKE SHORE Drive #12C, Chicago, IL 60657` appears in these results.

4. **Test with Property Description Only**
   ![Adobe Express - 2025-08-12_14-54-19.gif](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/1f25271c0e1c51a9e566474c5ae29c43/assets/Adobe%20Express%20-%202025-08-12_14-54-19.gif)
	 - Click **Reset All Boost to 0** under `Match Fields`
   - Configure **Location Filter**:
     - Latitude: `41.9172`
     - Longitude: `-87.6270`
	 - Click **Reset All Boost to 0** under `Match Fields`
   - Under **Text Fields**, select **Property Description**
   - Unselect all other fields
   - Run the same query
   ```
   Amazing lake view with an updated kitchen and a open floor plan
   ```
   **Observation:** Again note the position of `3534 N LAKE SHORE Drive #12C, Chicago, IL 60657` in these results.

5. **Enable RRF for Hybrid Search**
![Adobe Express - 2025-08-12_14-56-13.gif](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/a2f864b1adc7acb9521262d6bd31775f/assets/Adobe%20Express%20-%202025-08-12_14-56-13.gif)
	- Ensure **Body Content E5**, **Body Content ELSER**, and **Property Description** are all selected
   - Change **Retriever Type** to `RRF`
   - Run the same query
   ```
   Amazing lake view with an updated kitchen and a open floor plan
   ```
   **Expected Result:** `3534 N LAKE SHORE Drive #12C, Chicago, IL 60657` should now appear as the top result.

   **Key Insight:** RRF identifies documents that consistently appear across different search methods. Even if `3534 N LAKE SHORE Drive #12C, Chicago, IL 60657` wasn't the top result in all individual search method, its frequent occurrence across all three approaches signals strong overall relevance. RRF leverages this cross-method consensus to surface the most comprehensively relevant results.

Semantic Reranking
===

### About Semantic Reranking

Semantic reranking uses advanced language models to reorder search results based on semantic similarity rather than just keyword matching. This improves relevance by understanding the deeper meaning and context of queries and documents.

### Exercise: Before and After Semantic Reranking

1. **Test Without Semantic Reranking**

 - Set all **Search Component Weights** to `0`
   - Set **Retriever Type** to `Linear Retriever`
   - Configure **Location Filter**:
     - Latitude: `41.9172`
     - Longitude: `-87.6270`
   - Under **Match Fields**, select `Body Content E5`
   - Unselect all other fields
   - Run the query:
   ```
   Timeless home with lake views, French doors, and upscale kitchen
   ```
   **Observation:** Note that `728 W JACKSON Boulevard #313, Chicago, IL 60661` appears as a top result, but may not be the best semantic match for the query.

2. **Enable Semantic Reranking**
![Adobe Express - 2025-08-12_15-09-50.gif](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/5018decd6c9ee9ceb7ed3e89f5f20c34/assets/Adobe%20Express%20-%202025-08-12_15-09-50.gif)
	 - Set **Semantic Rerank** to `On`
   - Select `property description` as the reranking field
   - Run the same query

> [!NOTE]
> If you encounter a 408 or 409 error, that simply means the reranker model is currently deploying. This will occur when the model is first deployed.
> Wait a few minutes and rerun the query.

   **Expected Result:** The top result should now be `100 E Huron Street #2202, Chicago, IL 60611`, which better matches the semantic meaning of the query terms.

   **Key Insight:** Semantic reranking analyzes the actual content meaning rather than just keyword presence, leading to more contextually relevant results.

AI Infused Tuning
===

### About AI-Infused Tuning

AI-Infused Tuning provides intelligent recommendations for optimizing search configurations. The AI Advisor analyzes your current setup and search results to suggest specific parameter adjustments for improved relevance.

### Exercise: Using AI to Optimize Search Results
1. **Reset, Configure & Run Target Query**
![Adobe Express - 2025-08-13_14-24-48.gif](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/93cbbe4edbe096d9985e42ee3b0af764/assets/Adobe%20Express%20-%202025-08-13_14-24-48.gif)
   - Click **Reset All Boost to 0** under `Match Fields`
   - Enable **Explain** under `Search Settings` to see detailed scoring
   - Configure **Location Filter**:
     - Latitude: `41.9172`
     - Longitude: `-87.6270`
   - Disable **Semantic Reranking** (if previously enabled)
   - Execute the following query:
   ```
   Recently updated corner 2-bed with lake views and bay windows
   ```

3. **Analyze Target Document**
![Adobe Express - 2025-08-13_14-26-12.gif](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/8b841ba8fbfb37bc245911b31014a9f3/assets/Adobe%20Express%20-%202025-08-13_14-26-12.gif)
   - Locate `2422 N Racine Avenue #2, Chicago, IL 60614` within the results
   - Click the **Visual Score Breakdown** button for this property
   - Review the scoring details to understand why it's not ranking higher

4. **Get AI Recommendations**
![Adobe Express - 2025-08-13_14-33-56.gif](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/666c59ce3c35b6631abdb57eb75d6a91/assets/Adobe%20Express%20-%202025-08-13_14-33-56.gif)
   - Click the **Advisor** button to activate the AI tuning assistant
   - Ask the AI bot:
     ```
     What should I do to increase this doc score?
     ```
   - Review the AI's analysis and specific recommendations

5. **Apply Suggestions**
![Adobe Express - 2025-08-13_14-37-30.gif](https://play.instruqt.com/assets/tracks/fxsnxnkagvwd/1dc5b72ac92141843e1a746f9f4e07ca/assets/Adobe%20Express%20-%202025-08-13_14-37-30.gif)
   - Implement the AI Advisor's recommended weight adjustments
   - Re-run the query to measure improvement
   - Observe how the target property's ranking changes

   **Learning Objective:** Experience how machine learning can intelligently analyze search patterns and provide actionable optimization recommendations for specific use cases.

---

## Lab Summary

This lab demonstrated four key Elasticsearch capabilities:

1. **Multilingual Search**: Cross-language query capabilities with E5 embeddings
2. **Hybrid Search with RRF**: Combining multiple retrieval methods for better results
3. **Semantic Reranking**: Context-aware result ordering beyond keyword matching
4. **AI-Infused Tuning**: Intelligent optimization recommendations

Each technique addresses different search challenges and can be combined for optimal search experiences in production applications.