> **DEPRECATED — DO NOT TRUST THIS DOCUMENT.** Verified against real code on 2026-08-03:
> storage numbers (30MB/90MB/∞), Pro price ($4.99), and downgrade grace period (7 days) are
> all wrong. Real values live in `backend/config/settings.py` (`REPROOT_PLAN_TIERS`):
> 100MB/1GB/10GB storage, Pro $5.99/mo, 14-day grace. Phase 2 (file compression) described here
> was never built. This file is queued for deletion — see `AGENTS.md` for the rule covering
> this folder. Do not read this file as current product behavior.

# 3-Tier Data Usage Percentage Billing Migration Plan
**Status:** Approved & Work-in-Progress  
**Saved:** C:\Users\medas\Desktop\Application Development\RepRoot\BILLING_3TIER_PLAN.md

---

## QUICK SUMMARY
- **3 Tiers:** Starter Free | Pro ($4.99/mo) | Premium Unlimited ($14.99/mo)
- **Storage:** 30MB / 90MB / ∞
- **Warning:** 75% usage
- **Downgrade:** 7-day grace → Day 7 freeze → Day 30 data deletion
- **Features Locked on Downgrade:** Templates, Forms, Clients, Chat, References
- **New File Limits:** PDFs 5MB | Images 2-5MB per file
- **Compression:** User-choice (lossy JPEG or lossless PNG/WebP)
- **Chat Feature:** Add image sending + sensitive data warning banner

---

## NEW FEATURES (Phase 2 Addition)

### A. File Upload Limits & Compression

#### References Section
- **PDFs:** 5 MB limit per file (cloud cost optimized)
  - Covers: ~100-200 page documents, certificates, reports
  - Compression: User-choice at upload (optional auto-compress if over limit)
  
- **Images:** 2-5 MB per image
  - Compression options: Lossy (JPEG, 80% quality) or Lossless (PNG/WebP)
  - Auto-preview generation at 1000x1000px thumbnail

#### Chat Section (NEW)
- **Image Upload Capability:** Send images alongside text messages
- **Image Limits:** 2-5 MB per image (same as References)
- **Supported:** JPG, PNG, WebP, GIF (static only)

#### Payments Section
- **Invoice/Receipt Images:** 2-5 MB per file
- **Proof of Payment Attachments:** 5 MB limit (larger than standard images)

#### All Upload Endpoints
- Return **413 Payload Too Large** with suggestion: "File exceeds limit. Try: [Compress] [Upload Smaller] [Upgrade Plan]"
- Compression UI component: Show slider (quality 60-100%) before upload

### B. Compression Service (NEW)

**New File: `backend/accounts/file_utils.py`**

```python
def compress_image(file_bytes, format='jpeg', quality=80):
  """Compress image; return compressed bytes and new size"""
  # Uses PIL/Pillow
  # Returns: (compressed_bytes, original_size, compressed_size, savings_percent)

def compress_pdf(file_bytes, compression_level='default'):
  """Compress PDF using ghostscript or pypdf; return compressed bytes"""
  # Options: 'default' (5-10% reduction), 'high' (20-30% reduction)
  # Returns: (compressed_bytes, original_size, compressed_size)

def validate_and_compress(file_bytes, file_type, limit_mb, auto_compress=False):
  """Check size; auto-compress if requested and over limit"""
  # file_type: 'image' | 'pdf'
  # Returns: (final_bytes, info_dict with sizes/compression applied)
```

**Frontend: New Upload Component**

```html
<!-- shared/file-upload-modal.component.html -->
<div class="file-upload-modal">
  <input type="file" #fileInput (change)="onFileSelected($event)">
  
  @if (file) {
    <p>{{ file.name }} ({{ file.size | formatBytes }})</p>
    
    @if (file.size > limit) {
      <div class="compression-options">
        <p>File exceeds {{ limit | formatBytes }} limit.</p>
        
        @if (file.type.includes('image')) {
          <label>Compress image?
            <input type="range" min="60" max="100" [(ngModel)]="compressionQuality">
            {{ compressionQuality }}% quality
          </label>
          <button (click)="compressAndUpload('lossy')">Compress (JPEG)</button>
          <button (click)="compressAndUpload('lossless')">Compress (PNG)</button>
        }
        
        @if (file.type === 'pdf') {
          <button (click)="compressAndUpload('default')">Compress PDF</button>
        }
        
        <p><strong>Or upgrade plan</strong> for higher limits.</p>
      </div>
    } @else {
      <button (click)="upload()">Upload</button>
    }
  }
</div>
```

---

### C. Chat Enhancement: Image Sending + Sensitive Data Warning

#### New Feature: Image Upload in Chat

**File: `frontend/src/app/pages/studio/shared/chat-panel/chat-panel.component.html`**

Add image picker button next to message input:
```html
<div class="chat-input-row">
  <div class="message-input-area">
    <textarea [(ngModel)]="messageText" placeholder="Type message..."></textarea>
    
    <!-- Image upload button -->
    <button (click)="fileInput.click()" title="Send image">
      📎 Image
    </button>
    <input #fileInput type="file" accept="image/*" (change)="onImageSelected($event)" hidden>
    
    <!-- Image preview (if selected) -->
    @if (selectedImage) {
      <div class="image-preview">
        <img [src]="selectedImage.preview" alt="preview">
        <button (click)="clearImage()">✕</button>
      </div>
    }
  </div>
  
  <button (click)="sendMessage()" class="send-btn">Send</button>
</div>
```

#### Sensitive Data Warning Banner (NEW)

Add at top of chat:
```html
<div class="chat-warning-banner">
  ⚠️ <strong>Communication Only</strong>
  <p>This chat is for communication purposes only. 
  <strong>Do NOT send sensitive data</strong> such as:</p>
  <ul>
    <li>Credit card numbers, passwords, or financial info</li>
    <li>Social security numbers or government IDs</li>
    <li>Medical records or confidential health data</li>
    <li>Personal identification beyond name/email</li>
  </ul>
  <p>Messages and images are logged for support purposes. Use secure channels for sensitive information.</p>
</div>
```

#### Backend: Chat Message with Image

**File: `backend/accounts/views.py` (new endpoint)**

```python
@api_view(['POST'])
@permission_classes([IsAuthenticated])
def send_chat_message_with_image(request):
  message_text = request.data.get('message', '').strip()
  image_file = request.FILES.get('image')
  
  if not message_text and not image_file:
    return Response({'error': 'Message or image required'}, status=400)
  
  if image_file:
    # Validate size (2-5 MB)
    if image_file.size > 5 * 1024 * 1024:
      return Response({'error': 'Image exceeds 5 MB limit'}, status=413)
    
    # Store image in cloud storage (S3, etc)
    image_url = store_image(image_file)
  else:
    image_url = None
  
  # Create chat message record
  message = ChatMessage.objects.create(
    sender=request.professional,
    recipient=request.data.get('recipient_id'),
    text=message_text,
    image_url=image_url,
    message_type='text_with_image' if image_url else 'text'
  )
  
  return Response({ 'message_id': message.id, 'image_url': image_url })
```

#### Frontend: Display Chat Message with Image

```html
<!-- Chat message -->
<div class="chat-message" [class.mine]="message.sender_id === currentUser">
  <p>{{ message.text }}</p>
  
  @if (message.image_url) {
    <img [src]="message.image_url" alt="chat image" class="chat-image">
    <p class="image-caption">
      📷 Image sent at {{ message.created_at | date:'short' }}
    </p>
  }
</div>
```

---

## FILE SIZE RECOMMENDATIONS & CLOUD COST

### Storage Breakdown (Monthly Estimates)

| File Type | Limit | Typical Size | 1000 Users | Cloud Cost (AWS S3) |
|-----------|-------|--------------|-----------|-------------------|
| PDF (Reference) | 5 MB | 2-3 MB avg | ~2-3 GB | ~$0.05-0.07 |
| Images (all) | 2-5 MB | 1-2 MB avg | ~1-2 GB | ~$0.03-0.05 |
| Chat Images | 2-5 MB | 0.5-1 MB avg | ~500 MB | ~$0.015 |
| **Total** | | | **~3.5-5.5 GB** | **~$0.10-0.15** |

**Recommendation:** 5 MB for PDFs balances cloud cost ($0.05/mo per 1000 users) with usability (covers ~200-page documents).

---

## IMPLEMENTATION PHASES

### Phase 1: Core Billing (Weeks 1-4)
- 3-tier plan structure
- Account lifecycle (grace period, freezing)
- Feature locking

### Phase 2: File Upload & Compression (Weeks 4-6)
- File size validation on all endpoints
- Compression service (image + PDF)
- UI components for compression choice
- Apply to: References, Chat, Payments

### Phase 3: Chat Images + Warning (Weeks 6-7)
- Image upload in chat panel
- Sensitive data warning banner
- Message storage with image references

### Phase 4: Testing & Monitoring (Week 7+)
- Test file uploads near limits
- Monitor compression effectiveness
- Track cloud storage costs

---

## CRITICAL FILES TO UPDATE

**Backend:**
- `backend/accounts/file_utils.py` (NEW - compression service)
- `backend/accounts/views.py` (add file size validation to References, Chat, Payments endpoints)
- `backend/accounts/models.py` (add ChatMessage.image_url field)

**Frontend:**
- `frontend/src/app/pages/studio/shared/file-upload-modal/file-upload-modal.component.*` (NEW)
- `frontend/src/app/pages/studio/shared/chat-panel/chat-panel.component.*` (add image upload + warning banner)
- `frontend/src/app/pages/studio/professional/professional-references/` (integrate file upload component)
- `frontend/src/app/pages/studio/client/client-payments/` (integrate file upload for proofs)

---

## NEXT STEPS
1. ✅ Confirm PDF limit: 5 MB (or adjust?)
2. ✅ Confirm image limit: 2-5 MB per file
3. ✅ User choice compression: Offer lossy (JPEG 60-100%) + lossless (PNG/WebP)
4. ⏳ Phase 1: Implement core billing system
5. ⏳ Phase 2: File upload validation + compression
6. ⏳ Phase 3: Chat images + warning banner
7. ⏳ Deploy & monitor cloud costs

---

## NOTES
- Plan saved to: `C:\Users\medas\Desktop\Application Development\RepRoot\BILLING_3TIER_PLAN.md`
- Also in version control for reference
- Update this file as features are completed
- Cloud cost estimate: ~$0.10-0.15/month per 1000 users (S3 storage only, not data transfer)
