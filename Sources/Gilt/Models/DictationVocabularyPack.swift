import Foundation

/// Curated vocabulary packs the user can enable to teach the dictation
/// post-processor about domain-specific terminology.
///
/// Each pack is a list of *canonical* spellings (the way the term should
/// appear in the final transcript). The matcher generates likely spoken
/// variants on the fly — "API" → "a p i", "ChatGPT" → "chat g p t",
/// "useEffect" → "use effect", "Next.js" → "next js" — so users don't
/// have to enumerate every way Parakeet might mishear a term.
///
/// I deliberately exclude terms that collide with common English words —
/// "Go" (the language), "React" (the framework), "Java" (the coffee),
/// "Swift" (the adjective), "Apple", "Slack", "Drive", "Buffer". Adding
/// those would mangle casual sentences more often than they'd fix anything.
enum DictationVocabularyPack: String, Codable, CaseIterable, Identifiable, Hashable {
    case developer
    case marketer
    case academic
    case medical
    case legal
    case finance
    case design

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .developer: return "Developer"
        case .marketer: return "Marketer"
        case .academic: return "Academic"
        case .medical: return "Medical"
        case .legal: return "Legal"
        case .finance: return "Finance"
        case .design: return "Design"
        }
    }

    var subtitle: String {
        switch self {
        case .developer: return "APIs, frameworks, cloud services, React hooks, AI tooling, databases."
        case .marketer: return "KPIs, ad platforms, CRMs, analytics tools, funnel terminology."
        case .academic: return "Citation styles, statistics, research methodology, journals."
        case .medical: return "Conditions, drugs, procedures, specialties, vitals, EHR systems."
        case .legal: return "Court terminology, Latin phrases, contracts, IP, compliance frameworks."
        case .finance: return "Financial statements, derivatives, indices, regulators, crypto."
        case .design: return "Design tools, color systems, typography, file formats, design systems."
        }
    }

    var icon: String {
        switch self {
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .marketer: return "chart.line.uptrend.xyaxis"
        case .academic: return "graduationcap"
        case .medical: return "cross.case"
        case .legal: return "scale.3d"
        case .finance: return "dollarsign.circle"
        case .design: return "paintpalette"
        }
    }

    /// Canonical spellings the matcher will substitute back in. Each term
    /// is whole-word matched case-insensitively, plus auto-generated
    /// spoken variants (letter-spelled acronyms, camelCase splits, punct
    /// flattening).
    var terms: [String] {
        switch self {
        case .developer: return Self.developerTerms
        case .marketer: return Self.marketerTerms
        case .academic: return Self.academicTerms
        case .medical: return Self.medicalTerms
        case .legal: return Self.legalTerms
        case .finance: return Self.financeTerms
        case .design: return Self.designTerms
        }
    }

    /// Apply the user's per-pack edits to the curated list. Removals are
    /// matched case-insensitively so the user doesn't have to know which
    /// casing the curated entry uses; additions preserve the user's casing
    /// since that's the canonical spelling they want substituted back in.
    func effectiveTerms(additions: [String], removals: [String]) -> [String] {
        let removalSet = Set(removals.map { $0.lowercased() })
        let kept = terms.filter { !removalSet.contains($0.lowercased()) }
        // De-dupe additions against what's already kept so re-adding a
        // previously removed term doesn't double-fire the matcher.
        let keptLowered = Set(kept.map { $0.lowercased() })
        let extras = additions.filter { !keptLowered.contains($0.lowercased()) }
        return kept + extras
    }

    // MARK: - Pack contents
    //
    // These are stored as private static constants so the runtime cost of
    // `terms` is just an array reference, not a switch-and-rebuild every call.
    // Curated by hand to avoid common-English collisions; tested mentally
    // against the matcher's variant generator before inclusion.

    private static let developerTerms: [String] = [
        // Frameworks / libraries
        "TypeScript", "JavaScript", "Next.js", "Nuxt.js", "NestJS",
        "SvelteKit", "SolidJS", "Remix", "Astro", "Qwik",
        "RedwoodJS", "Gatsby", "Blitz.js", "Express.js", "Koa",
        "Fastify", "Hapi", "FastAPI", "Starlette", "Pyramid",
        "Phoenix LiveView", "htmx", "Alpine.js", "Stimulus", "Inertia",
        "Livewire", "Tailwind", "GraphQL", "gRPC", "tRPC", "Redux",
        "MobX", "Zustand", "Jotai", "Recoil", "TanStack Query",
        "SWR", "Apollo", "Relay", "RxJS",
        // Build tools / package managers
        "npm", "yarn", "pnpm", "bun", "Deno", "Webpack", "Vite",
        "esbuild", "Turbopack", "SWC", "Rollup", "Parcel", "Snowpack",
        "ESLint", "Prettier", "Biome", "Babel", "tsx", "ts-node",
        "nodemon", "PM2", "Cypress", "Playwright", "Puppeteer",
        "Jest", "Vitest", "Mocha", "Chai", "Sinon", "WebdriverIO",
        "Detox", "RSpec", "pytest", "JUnit", "XCTest",
        // Cloud / DevOps
        "AWS", "GCP", "Azure", "Vercel", "Netlify", "Cloudflare",
        "Heroku", "Render", "Railway", "Fly.io", "DigitalOcean",
        "Linode", "Vultr", "Lambda", "EC2", "RDS", "EKS", "ECS",
        "IAM", "VPC", "Route 53", "CloudFront", "CloudWatch",
        "CloudFormation", "Kubernetes", "Docker", "K8s", "Terraform",
        "Pulumi", "Helm", "ArgoCD", "FluxCD", "Istio", "Envoy",
        "Traefik", "nginx", "HAProxy", "Vagrant", "Packer", "Consul",
        "Vault", "Datadog", "Sentry", "Grafana", "Prometheus",
        "OpenTelemetry", "Splunk", "Logstash", "Kibana", "Elasticsearch",
        "GitHub", "GitLab", "Bitbucket", "Jenkins", "CircleCI",
        "GitHub Actions", "CI/CD",
        // Databases
        "PostgreSQL", "MongoDB", "DynamoDB", "MySQL", "MariaDB",
        "SQLite", "Redis", "Memcached", "Cassandra", "ScyllaDB",
        "ClickHouse", "DuckDB", "TimescaleDB", "InfluxDB", "Neo4j",
        "ArangoDB", "Couchbase", "RethinkDB", "CockroachDB", "FaunaDB",
        "PlanetScale", "Neon", "Turso", "Convex", "Hasura",
        "Supabase", "Firebase", "Snowflake", "BigQuery", "Databricks",
        "Prisma", "Drizzle", "TypeORM", "Sequelize", "Mongoose",
        "SQLAlchemy", "NoSQL",
        // Concepts / standards
        "API", "REST", "RESTful", "GraphQL", "JSON", "YAML", "TOML",
        "XML", "OAuth", "OAuth2", "OIDC", "SAML", "JWT", "CORS",
        "CSRF", "XSS", "SQLi", "RCE", "MITM", "DDoS", "HTTPS",
        "HTTP/2", "HTTP/3", "QUIC", "SSH", "DNS", "CDN", "SSR",
        "SSG", "ISR", "CSR", "RSC", "SPA", "PWA", "MVC", "MVVM",
        "ORM", "ODM", "CRUD", "SaaS", "PaaS", "IaaS", "TDD", "BDD",
        "DDD", "MVP", "POC", "WebSocket", "WebRTC", "WebGL", "WebGPU",
        "WASM", "WebAssembly", "JAMstack", "MERN", "MEAN", "LAMP",
        "CRDT", "CIDR", "IPv4", "IPv6", "TCP", "UDP", "ICMP",
        // React / Vue / Svelte
        "useEffect", "useState", "useMemo", "useCallback", "useRef",
        "useContext", "useReducer", "useLayoutEffect", "useImperativeHandle",
        "useDeferredValue", "useTransition", "useSyncExternalStore",
        "useId", "useFormState", "useActionState", "useOptimistic",
        "createSignal", "createEffect", "createMemo", "createResource",
        // AI / ML
        "ChatGPT", "OpenAI", "Anthropic", "Claude", "Gemini", "Mistral",
        "Llama", "Phi", "Qwen", "DeepSeek", "Grok",
        "LLM", "RAG", "LangChain", "LlamaIndex", "Hugging Face",
        "PyTorch", "TensorFlow", "JAX", "Keras", "scikit-learn",
        "Pandas", "NumPy", "SciPy", "MLflow", "Pinecone", "Weaviate",
        "Chroma", "FAISS", "Milvus", "Cohere", "Replicate", "Ollama",
        "vLLM", "llama.cpp", "GGUF", "ONNX",
        // Editors / dev tools
        "VSCode", "Cursor", "Zed", "JetBrains", "IntelliJ", "PyCharm",
        "WebStorm", "GoLand", "RubyMine", "Neovim", "Xcode",
        "Android Studio", "TablePlus", "Postman", "Insomnia", "Bruno",
        "Hoppscotch", "Copilot", "Codeium", "Tabnine", "Aider",
        // Misc concepts
        "monorepo", "microservice", "microservices", "idempotent",
        "idempotency", "polyfill", "transpile", "transpiler", "HMR",
        "treeshake", "codesplit", "bundler", "linter", "formatter",
        "typesafe", "typesafety", "DevEx", "DX", "FFI"
    ]

    private static let marketerTerms: [String] = [
        // Performance KPIs
        "CTR", "CPC", "CPM", "CPA", "CPL", "CPI", "CPV", "CPS",
        "ROAS", "ROI", "ROMI", "LTV", "CAC", "MRR", "ARR", "NRR",
        "GRR", "NDR", "AOV", "ARPU", "ARPPU", "NPS", "CSAT", "CES",
        "DAU", "MAU", "WAU", "DAUMAU", "TTV", "TTI",
        // Disciplines / channels
        "SEO", "SEM", "PPC", "SMM", "OOH", "DOOH", "CTV", "OTT",
        "UGC", "PR", "ASO", "ABM",
        // Ad platforms
        "Google Ads", "Meta Ads", "Facebook Ads", "Instagram Ads",
        "LinkedIn Ads", "TikTok Ads", "YouTube Ads", "Pinterest Ads",
        "Snapchat Ads", "Reddit Ads", "X Ads", "Quora Ads", "Bing Ads",
        "Microsoft Ads", "Apple Search Ads", "StackAdapt", "Trade Desk",
        "AppLovin", "Unity Ads", "ironSource", "AdMob", "AdSense",
        "AdManager", "GA4", "GTM", "DV360", "SA360",
        // CRM / Marketing automation / Email
        "HubSpot", "Salesforce", "Mailchimp", "Klaviyo", "Marketo",
        "Pardot", "ActiveCampaign", "ConvertKit", "Beehiiv", "Substack",
        "ConstantContact", "Sendinblue", "Brevo", "Customer.io",
        "OneSignal", "Iterable", "Braze", "Airship", "MoEngage",
        "Leanplum", "CleverTap", "Intercom", "Drift", "Zendesk",
        "Freshdesk", "Front", "Crisp", "LiveChat", "Helpscout",
        // Analytics
        "Mixpanel", "Amplitude", "Heap", "Hotjar", "FullStory",
        "LogRocket", "Plausible", "Fathom", "Clarity", "Smartlook",
        "Optimizely", "VWO", "Unbounce", "Instapage", "Leadpages",
        "ClickFunnels", "Tableau", "Looker", "Looker Studio", "Power BI",
        "Mode", "Metabase", "Sigma",
        // Concepts / methodology
        "AAARRR", "AARRR", "TOFU", "MOFU", "BOFU", "ICP", "TAM", "SAM",
        "SOM", "OKR", "KPI", "B2B", "B2C", "D2C", "B2B2C", "B2G",
        "MarTech", "AdTech", "FinTech", "EdTech", "HealthTech",
        "PropTech", "InsurTech", "GTM", "PMF", "PLG", "SLG", "PQL",
        "MQL", "SQL", "SAL", "SAO", "SDR", "BDR", "AE", "CSM",
        // Funnel / attribution
        "MMM", "MTA", "LDA", "BMM", "SERP", "SOV", "SOW", "CR",
        "CVR", "RPS", "EPC", "EPM", "RPM", "eCPM",
        // Email deliverability
        "SPF", "DKIM", "DMARC", "BIMI", "ESP", "SMTP", "IMAP",
        "MTA", "MX",
        // SEO toolset
        "Ahrefs", "SEMrush", "Moz", "Sistrix", "Screaming Frog",
        "Yoast", "RankMath", "SurferSEO", "Clearscope", "MarketMuse"
    ]

    private static let academicTerms: [String] = [
        // Citation styles
        "APA", "MLA", "Chicago", "Vancouver", "Harvard", "Turabian",
        "BibTeX", "DOI", "ISBN", "ISSN", "ORCID", "ResearcherID",
        "et al.", "ibid.", "op. cit.", "cf.", "viz.",
        // Statistics
        "ANOVA", "MANOVA", "ANCOVA", "MANCOVA", "p-value", "t-test",
        "chi-squared", "Kruskal-Wallis", "Mann-Whitney", "Wilcoxon",
        "Spearman", "Pearson", "Cohen's d", "Hedges' g", "RCT", "RDD",
        "regression", "logistic regression", "OLS", "GLM", "GLMM",
        "SEM", "CFA", "EFA", "PCA", "ICC", "Cronbach", "alpha",
        "heteroscedasticity", "multicollinearity", "autocorrelation",
        "endogeneity", "instrumental variable",
        // Methods
        "meta-analysis", "systematic review", "scoping review",
        "grounded theory", "phenomenology", "hermeneutics",
        "ethnography", "qualitative", "quantitative", "mixed-methods",
        "longitudinal", "cross-sectional", "case-control", "double-blind",
        "single-blind", "placebo", "ITT", "RCT",
        // Tools
        "SPSS", "SAS", "Stata", "RStudio", "Mendeley", "Zotero",
        "EndNote", "NVivo", "ATLAS.ti", "MAXQDA", "Overleaf", "LaTeX",
        "arXiv", "bioRxiv", "medRxiv", "SSRN",
        // Degrees / positions
        "PhD", "DPhil", "MSc", "MPhil", "MBA", "JD", "MD", "EdD",
        "DBA", "DSc", "MFA", "MEng", "postdoc", "ABD",
        // Concepts
        "peer review", "preprint", "h-index", "impact factor",
        "Web of Science", "Scopus", "PubMed", "JSTOR", "PRISMA",
        "Cochrane", "epistemology", "ontology", "falsifiability",
        "reproducibility", "replicability"
    ]

    private static let medicalTerms: [String] = [
        // Specialties
        "cardiology", "dermatology", "endocrinology", "gastroenterology",
        "hematology", "immunology", "nephrology", "neurology", "oncology",
        "ophthalmology", "orthopedics", "otolaryngology", "pathology",
        "pediatrics", "psychiatry", "pulmonology", "radiology",
        "rheumatology", "urology", "OB/GYN",
        // Conditions
        "hypertension", "hypotension", "hyperglycemia", "hypoglycemia",
        "tachycardia", "bradycardia", "arrhythmia", "AFib", "atrial fibrillation",
        "V-tach", "V-fib", "COPD", "GERD", "IBS", "IBD",
        "pneumonia", "sepsis", "bacteremia", "MRSA", "C. diff",
        // Vitals / labs
        "BP", "HR", "RR", "SpO2", "BMI", "BSA", "CBC", "CMP", "BMP",
        "LFT", "TFT", "INR", "PT", "PTT", "aPTT", "HbA1c", "A1C",
        "BNP", "troponin", "CK-MB", "TSH", "ALT", "AST", "BUN",
        "GFR", "eGFR",
        // Imaging / procedures
        "EKG", "ECG", "EEG", "EMG", "MRI", "CT", "PET", "CABG",
        "PCI", "stent", "angioplasty", "intubation", "extubation",
        "tracheostomy", "gastrostomy", "colostomy", "cholecystectomy",
        "appendectomy", "hysterectomy", "mastectomy", "endoscopy",
        "colonoscopy", "bronchoscopy",
        // Drug classes
        "ACE inhibitor", "ARB", "beta blocker", "diuretic", "statin",
        "SSRI", "SNRI", "MAOI", "NSAID", "PPI", "H2 blocker",
        "corticosteroid", "anticoagulant",
        // Specific drugs
        "amoxicillin", "ibuprofen", "acetaminophen", "lisinopril",
        "atorvastatin", "metformin", "omeprazole", "levothyroxine",
        "amlodipine", "metoprolol", "losartan", "sertraline",
        "fluoxetine", "gabapentin", "hydrochlorothiazide", "simvastatin",
        "montelukast", "warfarin", "heparin", "enoxaparin", "Lasix",
        "furosemide", "albuterol", "prednisone", "azithromycin",
        // Settings / roles
        "ICU", "NICU", "PICU", "CCU", "SICU", "MICU", "ED", "ER",
        "OR", "PACU", "L&D", "RN", "LPN", "CNA", "NP", "PA",
        "PharmD", "PT", "OT", "RT", "RD", "DDS", "DMD", "DPM", "DPT",
        // Systems
        "EHR", "EMR", "EPIC", "Cerner", "Meditech", "Allscripts",
        "athenahealth",
        // Regulatory / coding
        "HIPAA", "PHI", "ICD-10", "ICD-11", "CPT", "DRG", "HCPCS",
        "RVU", "NPI", "FDA", "CDC", "NIH", "CMS", "JCAHO",
        // Anatomy / route
        "cardiac", "hepatic", "renal", "pulmonary", "cerebral", "spinal",
        "GI", "GU", "MSK", "PO", "IV", "IM", "SubQ", "SQ", "PR", "SL"
    ]

    private static let legalTerms: [String] = [
        // Practice areas
        "tort", "contract", "constitutional", "administrative",
        "immigration", "antitrust", "securities",
        // Latin phrases
        "pro bono", "pro se", "pro hac vice", "ex parte", "amicus curiae",
        "mens rea", "actus reus", "prima facie", "res judicata",
        "stare decisis", "ipso facto", "de novo", "de jure", "de facto",
        "bona fide", "mala fide", "in toto", "ad hoc", "ad litem",
        "in rem", "in personam", "force majeure", "habeas corpus",
        "voir dire", "in camera", "in limine", "sua sponte",
        // Documents
        "NDA", "MOU", "MSA", "SOW", "LOI", "EULA", "ToS", "TOS",
        "RFP", "RFA", "RFQ",
        // Procedure
        "deposition", "affidavit", "subpoena", "interrogatory",
        "discovery", "complaint", "answer", "counterclaim", "summons",
        "indemnification", "indemnify", "estoppel", "tortious",
        "breach",
        // Courts / authorities
        "SCOTUS", "USDC", "COA", "AG", "DA", "USA",
        "certiorari", "mandamus", "appellant", "appellee",
        // Corporate / M&A
        "LLC", "LLP", "LP", "C-corp", "S-corp", "B-corp", "PBC",
        "IPO", "SPAC", "M&A", "LBO", "MBO", "ROFR", "ROFO",
        "drag-along", "tag-along", "anti-dilution",
        "liquidation preference", "EBITDA",
        // Compliance / regulation
        "SOX", "GDPR", "CCPA", "CPRA", "HIPAA", "FERPA", "COPPA",
        "PCI DSS", "GLBA", "SOC 2", "ISO 27001", "OFAC", "FCPA",
        // IP
        "USPTO", "EPO", "WIPO", "PCT", "ITC", "OA", "IDS",
        "trademark", "copyright", "utility patent", "design patent",
        "provisional", "non-provisional", "prior art", "FTO",
        "IPR", "PGR", "CBM", "CIP", "TM", "DMCA"
    ]

    private static let financeTerms: [String] = [
        // Roles / certs
        "CFO", "CPA", "CFA", "CMT", "CAIA", "FRM", "ChFC", "CIMA",
        "FP&A", "VP", "MD",
        // Statements / filings
        "P&L", "MD&A", "10-K", "10-Q", "8-K", "S-1", "S-4", "13F",
        "13D", "DEF 14A", "GAAP", "IFRS", "FASB", "IASB",
        // Metrics
        "EPS", "EBITDA", "EBIT", "NOPAT", "FCF", "OCF", "FCFF", "FCFE",
        "WACC", "ROE", "ROA", "ROIC", "ROCE", "COGS", "SG&A", "OpEx",
        "CapEx", "D&A", "CAC", "LTV", "MRR", "ARR", "NRR", "GRR",
        "NPV", "IRR", "DCF", "NAV", "AUM", "P/E", "P/B", "P/S",
        "P/CF", "PEG", "DDM",
        // Markets / instruments
        "NYSE", "NASDAQ", "LSE", "TSX", "HKEX", "ETF", "REIT",
        "MBS", "ABS", "CDO", "CLO", "CDS", "IRS", "FRA", "FX",
        "ITM", "OTM", "ATM",
        // Greeks
        "theta", "gamma", "delta", "vega", "rho", "vanna", "charm",
        "vomma",
        // Indices
        "S&P 500", "S&P", "DJIA", "Russell", "FTSE", "DAX", "CAC",
        "Nikkei", "Hang Seng", "VIX",
        // Trading concepts
        "TWAP", "VWAP", "POV", "IOC", "FOK", "GTC", "GTD", "AON",
        "HFT", "ATS", "ECN", "MM",
        // Crypto
        "BTC", "ETH", "USDC", "USDT", "DAI", "EVM", "DeFi", "TVL",
        "APR", "APY", "AMM", "DEX", "CEX", "NFT", "DAO", "KYC",
        "AML", "MEV", "EIP", "ERC-20", "ERC-721", "ERC-1155",
        "L1", "L2", "zkEVM", "ZK-rollup", "optimistic rollup",
        // Corporate finance
        "PIPE", "convertible note", "SAFE", "ESOP", "RSU", "ISO",
        "NSO", "NQSO", "QSBS", "409A", "83(b)",
        // Firms / banks
        "Goldman Sachs", "JPM", "BofA", "BlackRock", "Vanguard",
        "Fidelity", "Schwab", "Robinhood", "Coinbase", "Binance",
        // Regulators
        "SEC", "FINRA", "CFTC", "OCC", "FDIC", "FRB", "FOMC", "FCA",
        "BoE", "ECB", "BoJ", "PBoC", "MAS", "IMF", "BIS", "FATF",
        "EDD", "CDD", "SAR", "CTR",
        // Accounting
        "AR", "AP", "GL", "T&E", "FIFO", "LIFO"
    ]

    private static let designTerms: [String] = [
        // Tools
        "Figma", "FigJam", "Sketch", "InVision", "Framer", "Penpot",
        "Affinity", "Procreate", "Photoshop", "Illustrator", "InDesign",
        "After Effects", "Premiere Pro", "Lightroom", "Blender",
        "Cinema 4D", "ZBrush", "Maya", "Houdini", "Spline", "Rive",
        "Lottie", "Adobe XD",
        // Disciplines / concepts
        "UX", "UI", "IxD", "IA", "CX", "EX", "HCI", "A11y", "ARIA",
        "WCAG", "AA", "AAA",
        // Typography
        "kerning", "leading", "tracking", "ligature", "hinting",
        "anti-aliasing", "subpixel", "OpenType", "OTF", "TTF",
        "WOFF", "WOFF2",
        // Color systems
        "RGB", "RGBA", "HSL", "HSLA", "HSV", "CMYK", "P3", "sRGB",
        "Rec. 709", "Rec. 2020", "DPI", "PPI", "HiDPI",
        // Aesthetics
        "skeuomorphism", "neumorphism", "brutalism", "minimalism",
        "glassmorphism", "claymorphism", "parallax",
        // Easing / motion
        "ease-in", "ease-out", "ease-in-out", "lerp",
        // File formats
        "PSD", "AI", "INDD", "AEP", "PRPROJ", "SVG", "WebP", "AVIF",
        "HEIC", "ProRes", "H.264", "H.265", "HEVC", "AV1",
        // Design systems / UI frameworks
        "Material Design", "Material 3", "Tailwind", "shadcn", "Radix",
        "Headless UI", "Mantine", "Chakra", "MUI", "Material UI",
        "Ant Design", "Bootstrap", "Polaris", "Fluent", "Carbon",
        "Apple HIG", "HIG", "NN/g"
    ]
}
