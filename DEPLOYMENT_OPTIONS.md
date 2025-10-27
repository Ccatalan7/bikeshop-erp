# 🚀 Deployment Options for Bikeshop ERP

This app can be deployed to **multiple hosting providers**. Choose the one that fits your needs.

---

## 📦 Option 1: Firebase Hosting (Current Setup)

**Status**: ✅ Already configured  
**Best for**: Simple deployment, Google Cloud integration  
**Cost**: Free tier (10 GB/month bandwidth)

### Current Configuration:
- **ERP/Admin**: `project-vinabike.web.app`
- **Public Store**: `vinabike-store.web.app`

### Deploy:
```bash
# Build the app
flutter build web --release

# Deploy both sites
firebase deploy --only hosting

# Or deploy individually
firebase deploy --only hosting:erp
firebase deploy --only hosting:store
```

### Pros:
- ✅ Already set up
- ✅ Free SSL
- ✅ CDN included
- ✅ Easy rollback

### Cons:
- ❌ No wildcard subdomain support on free tier
- ❌ Custom domain costs extra

---

## 🔷 Option 2: Vercel (Recommended for Multi-Tenant)

**Status**: ⚙️ Configuration ready (`vercel.json`)  
**Best for**: Wildcard subdomains, custom domains, multi-tenant SaaS  
**Cost**: Free tier (100 GB/month bandwidth)

### Why Vercel for Multi-Tenant?
- ✅ **Free wildcard subdomains** (`*.bikeshop-erp.app`)
- ✅ **Automatic SSL** for all subdomains
- ✅ **Fast edge network**
- ✅ **Easy custom domain setup**

### Deploy:
```bash
# Install Vercel CLI
npm install -g vercel

# Login
vercel login

# Deploy (preview)
vercel

# Deploy (production)
vercel --prod
```

### Setup Wildcard Subdomain:
1. Buy domain: `bikeshop-erp.app` (~$12/year)
2. Add to Vercel project
3. Configure DNS:
   - Add A record: `@` → Vercel IP
   - Add CNAME: `*.bikeshop-erp.app` → `cname.vercel-dns.com`
4. Vercel auto-provisions SSL

### Result:
- Main site: `bikeshop-erp.app`
- Tenant 1: `vinabike.bikeshop-erp.app`
- Tenant 2: `joesbikes.bikeshop-erp.app`
- Custom: `www.vinabike.cl` (CNAME to subdomain)

---

## 🟢 Option 3: Netlify

**Status**: ⚙️ Configuration ready (`netlify.toml`)  
**Best for**: Simple deployment, serverless functions  
**Cost**: Free tier (100 GB/month bandwidth)

### Deploy:
```bash
# Install Netlify CLI
npm install -g netlify-cli

# Login
netlify login

# Deploy (preview)
netlify deploy

# Deploy (production)
netlify deploy --prod
```

### Pros:
- ✅ Generous free tier
- ✅ Free SSL
- ✅ Serverless functions
- ✅ Build previews

### Cons:
- ❌ Wildcard subdomains only on paid plan ($19/month)

---

## 🐳 Option 4: Docker + Self-Hosted

**Status**: ⚙️ Can create `Dockerfile` if needed  
**Best for**: Full control, existing infrastructure  
**Cost**: Server hosting costs

### Deploy:
```bash
# Build Docker image
docker build -t bikeshop-erp .

# Run container
docker run -p 80:80 bikeshop-erp

# Or use docker-compose
docker-compose up -d
```

### Pros:
- ✅ Full control
- ✅ No vendor lock-in
- ✅ Can run on any cloud (AWS, DigitalOcean, etc.)

### Cons:
- ❌ Requires DevOps knowledge
- ❌ Manual SSL setup (Let's Encrypt)
- ❌ Manual scaling

---

## 🌐 Option 5: GitHub Pages

**Status**: Not recommended (no SPA routing support)  
**Best for**: Static sites only  
**Cost**: Free

### Why NOT recommended:
- ❌ No server-side routing
- ❌ No custom headers
- ❌ No wildcard subdomains
- ❌ Complicated SPA setup

---

## 📊 Comparison Table

| Feature | Firebase | Vercel | Netlify | Self-Hosted |
|---------|----------|--------|---------|-------------|
| **Free Tier Bandwidth** | 10 GB | 100 GB | 100 GB | Unlimited* |
| **Wildcard Subdomains** | ❌ | ✅ Free | 💰 $19/mo | ✅ Manual |
| **Auto SSL** | ✅ | ✅ | ✅ | ⚙️ Manual |
| **CDN** | ✅ | ✅ | ✅ | ❌ |
| **Build Time** | Fast | Fast | Fast | N/A |
| **Custom Domains** | ✅ | ✅ | ✅ | ✅ |
| **Rollback** | ✅ | ✅ | ✅ | ⚙️ Manual |
| **Setup Difficulty** | Easy | Easy | Easy | Hard |

---

## 🎯 Recommendation by Use Case

### **Single Tenant (1 shop)**
→ Use **Firebase Hosting** (already set up)

### **Multi-Tenant SaaS (many shops)**
→ Use **Vercel** (best wildcard support)

### **Enterprise/Self-Hosted**
→ Use **Docker** on your own servers

### **Hybrid Approach**
→ Keep **Firebase** for ERP/Admin, use **Vercel** for public storefronts

---

## 🔧 Quick Start Guide

### For Firebase (Current):
```bash
firebase deploy --only hosting
```

### For Vercel (Multi-Tenant):
```bash
vercel --prod
```

### For Netlify:
```bash
netlify deploy --prod
```

### For Docker:
```bash
docker-compose up -d
```

---

## 📝 Notes

- All configurations are **already created** in this repo
- You can deploy to **multiple providers** simultaneously (e.g., Firebase for admin, Vercel for stores)
- Switching providers is easy - just run the appropriate deploy command
- **No code changes needed** - the Flutter web app works everywhere

---

## 🆘 Need Help?

- **Firebase**: Check `firebase.json` and `README.md`
- **Vercel**: Check `vercel.json`
- **Netlify**: Check `netlify.toml`
- **Docker**: Request `Dockerfile` creation

**Choose the option that best fits your business model!** 🚀
