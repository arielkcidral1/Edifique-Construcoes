const SUPABASE_URL = "https://uimjqymytxqvvwrojcgg.supabase.co";

const SUPABASE_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVpbWpxeW15dHhxdnZ3cm9qY2dnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwMzU2NzQsImV4cCI6MjA5NTYxMTY3NH0.6hEL8U6gEvAFmMbXsu5B9OPeI90E-7flfqWqzrHZPa4";

const db = window.supabase
  ? window.supabase.createClient(
      SUPABASE_URL,
      SUPABASE_ANON_KEY
    )
  : null;

const ADMIN_EMAIL = "admin@edifique.com";

let clienteLogado = null;
let adminLogado = false;
let projectAlbums = [];

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function escapeAttr(value) {
  return escapeHtml(value).replace(/`/g, "&#096;");
}

function normalizeEmail(value) {
  return (value || "").trim().toLowerCase();
}

function normalizeCpf(value) {
  return (value || "").replace(/\D/g, "");
}

function formatCpf(value) {
  return normalizeCpf(value)
    .slice(0, 11)
    .replace(/(\d{3})(\d)/, "$1.$2")
    .replace(/(\d{3})(\d)/, "$1.$2")
    .replace(/(\d{3})(\d{1,2})$/, "$1-$2");
}

function formatPhone(value) {
  const digits = (value || "").replace(/\D/g, "").slice(0, 11);
  if (digits.length <= 10) {
    return digits
      .replace(/(\d{2})(\d)/, "($1) $2")
      .replace(/(\d{4})(\d)/, "$1-$2");
  }
  return digits
    .replace(/(\d{2})(\d)/, "($1) $2")
    .replace(/(\d{5})(\d)/, "$1-$2");
}

function getFirstName(name) {
  return (name || "Cliente").trim().split(" ")[0] || "Cliente";
}

function getInitials(name) {
  return (name || "Cliente")
    .trim()
    .split(/\s+/)
    .map((part) => part[0])
    .join("")
    .substring(0, 2)
    .toUpperCase() || "CL";
}

function renderAvatarContent(name, avatarUrl = "", className = "") {
  if (avatarUrl) {
    return `<img class="${className}" src="${escapeHtml(avatarUrl)}" alt="Foto de ${escapeHtml(name || "cliente")}">`;
  }

  return escapeHtml(getInitials(name));
}

function updateClientSessionUI() {
  const btn = document.getElementById("clientSessionBtn");
  if (!btn) return;

  const label = btn.querySelector("span");
  if (adminLogado) {
    document.body.classList.remove("client-logged-in");
    btn.hidden = false;
    btn.removeAttribute("aria-hidden");
    if (label) label.textContent = "Painel Admin";
    btn.title = "Abrir painel administrativo";
    return;
  }

  btn.hidden = false;
  btn.removeAttribute("aria-hidden");
  if (clienteLogado) {
    document.body.classList.add("client-logged-in");
    if (label) label.textContent = getFirstName(clienteLogado.name);
    btn.title = `Cliente logado: ${clienteLogado.name || clienteLogado.email}`;
  } else {
    document.body.classList.remove("client-logged-in");
    if (label) label.textContent = "Entrar Cliente";
    btn.title = "Conta do cliente";
  }
}

async function updateCondominiumsMenu() {
  const links = document.querySelectorAll("[data-condominiums-link]");
  if (!links.length) return;

  links.forEach((link) => { link.hidden = true; });
  if (!db || adminLogado || !clienteLogado?.id) return;

  const { count, error } = await db
    .from("customer_condominiums")
    .select("id", { count: "exact", head: true })
    .eq("customer_id", clienteLogado.id);

  if (!error && count > 0) {
    links.forEach((link) => { link.hidden = false; });
  }
}

function switchClientAuthTab(tab) {
  document.querySelectorAll(".client-auth-tab").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.clientAuthTab === tab);
  });

  document.querySelectorAll(".client-auth-form").forEach((form) => {
    form.classList.toggle(
      "active",
      form.id === (tab === "register" ? "formClienteCadastro" : "formClienteLogin")
    );
  });

  const loginError = document.getElementById("clienteLoginError");
  const cadastroError = document.getElementById("clienteCadastroError");
  if (loginError) loginError.textContent = "";
  if (cadastroError) cadastroError.textContent = "";
}

function showClientAuth(tab = "login") {
  const overlay = document.getElementById("clientAuthOverlay");
  if (!overlay) return;

  overlay.classList.add("open");
  overlay.setAttribute("aria-hidden", "false");
  switchClientAuthTab(tab);

  setTimeout(() => {
    const first = document.querySelector(".client-auth-form.active input");
    if (first) first.focus();
  }, 80);
}

function closeClientAuth() {
  const overlay = document.getElementById("clientAuthOverlay");
  if (!overlay) return;
  overlay.classList.remove("open");
  overlay.setAttribute("aria-hidden", "true");
}

function showReviewForm() {
  const overlay = document.getElementById("reviewOverlay");
  if (!overlay) return;
  overlay.classList.add("open");
  overlay.setAttribute("aria-hidden", "false");

  setTimeout(() => {
    const comment = document.getElementById("reviewComment");
    if (comment) comment.focus();
  }, 80);
}

function closeReviewForm() {
  const overlay = document.getElementById("reviewOverlay");
  if (!overlay) return;
  overlay.classList.remove("open");
  overlay.setAttribute("aria-hidden", "true");
}

// ===============================
// PAINEL DE CONTA DO CLIENTE
// ===============================
function showAccountPanel() {
  let panel = document.getElementById("accountPanel");
  if (!panel) {
    panel = buildAccountPanel();
    document.body.appendChild(panel);
  }
  populateAccountPanel();
  panel.classList.add("open");
  panel.setAttribute("aria-hidden", "false");
}

function closeAccountPanel() {
  const panel = document.getElementById("accountPanel");
  if (!panel) return;
  panel.classList.remove("open");
  panel.setAttribute("aria-hidden", "true");
}

function buildAccountPanel() {
  const panel = document.createElement("div");
  panel.id = "accountPanel";
  panel.className = "account-panel-overlay";
  panel.setAttribute("aria-hidden", "true");
  panel.innerHTML = `
    <div class="account-panel" role="dialog" aria-modal="true" aria-labelledby="accountPanelTitle">

      <!-- SIDEBAR -->
      <aside class="account-sidebar">
        <div class="account-sidebar-header">
          <div class="account-avatar-lg" id="accountAvatarSidebar">CL</div>
          <div class="account-sidebar-info">
            <span class="account-sidebar-name" id="accountSidebarName">Cliente</span>
            <span class="account-sidebar-email" id="accountSidebarEmail">—</span>
          </div>
        </div>
        <nav class="account-nav">
          <button class="account-nav-item active" data-account-tab="perfil">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
            Meu Perfil
          </button>
          <button class="account-nav-item" data-account-tab="seguranca">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
            Segurança
          </button>
          <button class="account-nav-item" data-account-tab="avaliacoes">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>
            Minhas Avaliações
          </button>
          <div class="account-nav-spacer"></div>
          <button class="account-logout-btn" id="accountLogoutBtn">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
            Sair da conta
          </button>
        </nav>
      </aside>

      <!-- MAIN CONTENT -->
      <main class="account-main">
        <div class="account-main-header">
          <h2 id="accountPanelTitle">Configurações da Conta</h2>
          <button class="account-close-btn" id="accountPanelClose" aria-label="Fechar painel">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>

        <!-- TAB: PERFIL -->
        <div class="account-tab-content active" id="account-tab-perfil">
          <div class="account-section-label">Informações pessoais</div>
          <p class="account-section-desc">Mantenha seus dados atualizados para um atendimento mais ágil.</p>

          <form id="accountProfileForm" class="account-form" novalidate>
            <div class="account-photo-field">
              <div class="account-photo-preview" id="accountPhotoPreview">CL</div>
              <div class="account-photo-copy">
                <label for="accountPhoto">Foto do perfil</label>
                <span class="account-field-hint">Use uma imagem JPG, PNG ou WebP com ate 2 MB.</span>
                <input type="file" id="accountPhoto" accept="image/png,image/jpeg,image/webp">
              </div>
            </div>
            <div class="account-field-group">
              <div class="account-field">
                <label for="accountNome">Nome completo</label>
                <input type="text" id="accountNome" placeholder="Seu nome completo" required>
              </div>
              <div class="account-field">
                <label for="accountEmail">E-mail</label>
                <input type="email" id="accountEmail" placeholder="seu@email.com" readonly>
                <span class="account-field-hint">O e-mail não pode ser alterado aqui.</span>
              </div>
            </div>
            <div class="account-field-group">
              <div class="account-field">
                <label for="accountCpf">CPF</label>
                <input type="text" id="accountCpf" placeholder="000.000.000-00" maxlength="14">
              </div>
              <div class="account-field">
                <label for="accountPhone">WhatsApp</label>
                <input type="tel" id="accountPhone" placeholder="(00) 00000-0000">
              </div>
            </div>
            <span class="account-feedback" id="accountProfileFeedback"></span>
            <div class="account-form-actions">
              <button type="submit" class="account-btn-save">Salvar alterações</button>
            </div>
          </form>
        </div>

        <!-- TAB: SEGURANÇA -->
        <div class="account-tab-content" id="account-tab-seguranca">
          <div class="account-section-label">Senha e acesso</div>
          <p class="account-section-desc">Altere sua senha para manter sua conta segura.</p>

          <form id="accountPasswordForm" class="account-form" novalidate>
            <div class="account-field">
              <label for="accountPassNew">Nova senha</label>
              <input type="password" id="accountPassNew" placeholder="Mínimo 6 caracteres" minlength="6" required>
            </div>
            <div class="account-field">
              <label for="accountPassConfirm">Confirmar nova senha</label>
              <input type="password" id="accountPassConfirm" placeholder="Repita a nova senha" required>
            </div>
            <span class="account-feedback" id="accountPasswordFeedback"></span>
            <div class="account-form-actions">
              <button type="submit" class="account-btn-save">Atualizar senha</button>
            </div>
          </form>

          <div class="account-danger-zone">
            <div class="account-section-label" style="color:#ff8a78;">Zona de perigo</div>
            <p class="account-section-desc">Esta ação é permanente e não pode ser desfeita.</p>
            <button class="account-btn-danger" id="accountDeleteBtn">Excluir minha conta</button>
          </div>
        </div>

        <!-- TAB: AVALIAÇÕES -->
        <div class="account-tab-content" id="account-tab-avaliacoes">
          <div class="account-section-label">Histórico de avaliações</div>
          <p class="account-section-desc">Avaliações que você enviou para a Edifique Construções.</p>
          <div class="account-reviews-list" id="accountReviewsList">
            <div class="account-reviews-loading">Carregando avaliações...</div>
          </div>
        </div>

      </main>
    </div>
  `;

  // Tab navigation
  panel.querySelectorAll("[data-account-tab]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const tab = btn.dataset.accountTab;
      panel.querySelectorAll(".account-nav-item").forEach(b => b.classList.remove("active"));
      btn.classList.add("active");
      panel.querySelectorAll(".account-tab-content").forEach(c => c.classList.remove("active"));
      const content = panel.querySelector(`#account-tab-${tab}`);
      if (content) content.classList.add("active");
      if (tab === "avaliacoes") loadAccountReviews();
    });
  });

  // Close
  panel.querySelector("#accountPanelClose").addEventListener("click", closeAccountPanel);
  panel.addEventListener("click", (e) => {
    if (e.target === panel) closeAccountPanel();
  });

  // Logout
  panel.querySelector("#accountLogoutBtn").addEventListener("click", async () => {
    await db.auth.signOut();
    clienteLogado = null;
    updateClientSessionUI();
    await updateCondominiumsMenu();
    closeAccountPanel();
  });

  // CPF / Phone masks
  panel.querySelector("#accountCpf").addEventListener("input", function () {
    this.value = formatCpf(this.value);
  });
  panel.querySelector("#accountPhone").addEventListener("input", function () {
    this.value = formatPhone(this.value);
  });
  panel.querySelector("#accountPhoto").addEventListener("change", function () {
    const file = this.files?.[0];
    const preview = document.getElementById("accountPhotoPreview");
    const feedback = document.getElementById("accountProfileFeedback");
    if (feedback) {
      feedback.textContent = "";
      feedback.className = "account-feedback";
    }
    if (!file || !preview) return;
    if (!file.type.startsWith("image/") || file.size > 2 * 1024 * 1024) {
      this.value = "";
      if (feedback) {
        feedback.textContent = "Escolha uma imagem JPG, PNG ou WebP com ate 2 MB.";
        feedback.classList.add("error");
      }
      return;
    }
    const objectUrl = URL.createObjectURL(file);
    preview.innerHTML = `<img src="${objectUrl}" alt="Previa da foto do perfil">`;
  });

  // Profile form
  panel.querySelector("#accountProfileForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    const feedback = document.getElementById("accountProfileFeedback");
    feedback.textContent = "";
    feedback.className = "account-feedback";

    const name = document.getElementById("accountNome").value.trim();
    const cpf = document.getElementById("accountCpf").value.trim();
    const phone = document.getElementById("accountPhone").value.trim();
    const email = clienteLogado?.email || "";
    const photoInput = document.getElementById("accountPhoto");
    const photoFile = photoInput?.files?.[0] || null;

    if (!name) { feedback.textContent = "Informe seu nome."; feedback.classList.add("error"); return; }
    if (photoFile && (!photoFile.type.startsWith("image/") || photoFile.size > 2 * 1024 * 1024)) {
      feedback.textContent = "Escolha uma imagem JPG, PNG ou WebP com ate 2 MB.";
      feedback.classList.add("error");
      return;
    }

    const btn = e.target.querySelector("button[type=submit]");
    btn.disabled = true;
    try {
      const { error } = await db.rpc("upsert_customer_profile", {
        name_input: name,
        email_input: email,
        cpf_input: cpf,
        phone_input: phone
      });
      if (error) throw error;
      await loadClientProfile();
      let avatarUrl = clienteLogado?.avatar_url || "";
      if (photoFile) {
        avatarUrl = await uploadCustomerAvatar(photoFile);
        const { error: avatarError } = await db
          .from("customers")
          .update({ avatar_url: avatarUrl })
          .eq("id", clienteLogado.id);
        if (avatarError) throw avatarError;
      }
      await loadClientProfile();
      if (clienteLogado?.id) {
        await db
          .from("reviews")
          .update({
            reviewer_name: clienteLogado.name || name,
            reviewer_avatar_url: clienteLogado.avatar_url || avatarUrl || null
          })
          .eq("customer_id", clienteLogado.id);
      }
      populateAccountPanel();
      const testimonialsData = await fetchTestimonialsData();
      renderTestimonials(testimonialsData);
      setupRevealAnimation();
      if (photoInput) photoInput.value = "";
      feedback.textContent = "Perfil atualizado com sucesso!";
      feedback.classList.add("success");
    } catch (err) {
      feedback.textContent = "Não foi possível salvar. Tente novamente.";
      feedback.classList.add("error");
    } finally {
      btn.disabled = false;
    }
  });

  // Password form
  panel.querySelector("#accountPasswordForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    const feedback = document.getElementById("accountPasswordFeedback");
    feedback.textContent = "";
    feedback.className = "account-feedback";

    const newPass = document.getElementById("accountPassNew").value;
    const confirmPass = document.getElementById("accountPassConfirm").value;

    if (newPass.length < 6) { feedback.textContent = "A senha deve ter pelo menos 6 caracteres."; feedback.classList.add("error"); return; }
    if (newPass !== confirmPass) { feedback.textContent = "As senhas não coincidem."; feedback.classList.add("error"); return; }

    const btn = e.target.querySelector("button[type=submit]");
    btn.disabled = true;
    try {
      const { error } = await db.auth.updateUser({ password: newPass });
      if (error) throw error;
      e.target.reset();
      feedback.textContent = "Senha alterada com sucesso!";
      feedback.classList.add("success");
    } catch (err) {
      feedback.textContent = "Não foi possível alterar a senha.";
      feedback.classList.add("error");
    } finally {
      btn.disabled = false;
    }
  });

  // Delete account
  panel.querySelector("#accountDeleteBtn").addEventListener("click", async () => {
    if (!confirm("Tem certeza que deseja excluir sua conta? Esta ação é permanente.")) return;
    // sign out first – server-side deletion requires service role; for now we sign out and inform
    await db.auth.signOut();
    clienteLogado = null;
    updateClientSessionUI();
    await updateCondominiumsMenu();
    closeAccountPanel();
    alert("Sua solicitação de exclusão foi registrada. Entraremos em contato para concluir o processo.");
  });

  return panel;
}

function populateAccountPanel() {
  if (!clienteLogado) return;

  const name = clienteLogado.name || "Cliente";
  const email = clienteLogado.email || "—";
  const avatarUrl = clienteLogado.avatar_url || "";

  const avatarEl = document.getElementById("accountAvatarSidebar");
  const photoPreviewEl = document.getElementById("accountPhotoPreview");
  const nameEl = document.getElementById("accountSidebarName");
  const emailEl = document.getElementById("accountSidebarEmail");

  if (avatarEl) avatarEl.innerHTML = renderAvatarContent(name, avatarUrl, "account-avatar-img");
  if (photoPreviewEl) photoPreviewEl.innerHTML = renderAvatarContent(name, avatarUrl, "account-avatar-img");
  if (nameEl) nameEl.textContent = getFirstName(name);
  if (emailEl) emailEl.textContent = email;

  const nomeInput = document.getElementById("accountNome");
  const emailInput = document.getElementById("accountEmail");
  const cpfInput = document.getElementById("accountCpf");
  const phoneInput = document.getElementById("accountPhone");

  if (nomeInput) nomeInput.value = name;
  if (emailInput) emailInput.value = email;
  if (cpfInput) cpfInput.value = clienteLogado.cpf ? formatCpf(clienteLogado.cpf) : "";
  if (phoneInput) phoneInput.value = clienteLogado.phone ? formatPhone(clienteLogado.phone) : "";
}

async function loadAccountReviews() {
  const container = document.getElementById("accountReviewsList");
  if (!container || !db) return;

  container.innerHTML = '<div class="account-reviews-loading">Carregando avaliações...</div>';

  try {
    const { data: sessionData } = await db.auth.getSession();
    const user = sessionData?.session?.user;
    if (!user) { container.innerHTML = '<p class="account-reviews-empty">Faça login para ver suas avaliações.</p>'; return; }

    const { data: customer } = await db.from("customers").select("id").eq("user_id", user.id).maybeSingle();
    if (!customer) { container.innerHTML = '<p class="account-reviews-empty">Nenhuma avaliação encontrada.</p>'; return; }

    const { data, error } = await db.from("reviews")
      .select("id, rating, comment, created_at, projects(name)")
      .eq("customer_id", customer.id)
      .order("created_at", { ascending: false });

    if (error) throw error;

    if (!data.length) {
      container.innerHTML = '<p class="account-reviews-empty">Você ainda não enviou nenhuma avaliação.</p>';
      return;
    }

    container.innerHTML = data.map(rev => `
      <div class="account-review-card">
        <div class="account-review-header">
          <span class="account-review-stars">${"★".repeat(rev.rating)}${"☆".repeat(5 - rev.rating)}</span>
          <span class="account-review-project">${escapeHtml(rev.projects?.name || "Edifique Construções")}</span>
        </div>
        <p class="account-review-text">${escapeHtml(rev.comment || "")}</p>
        <span class="account-review-date">${new Date(rev.created_at).toLocaleDateString("pt-BR", { day:"2-digit", month:"long", year:"numeric" })}</span>
      </div>
    `).join("");
  } catch (err) {
    container.innerHTML = '<p class="account-reviews-empty">Erro ao carregar avaliações.</p>';
  }
}

async function resolveEmailFromCredential(credential) {
  if (credential.includes("@")) return normalizeEmail(credential);

  const cpf = normalizeCpf(credential);
  if (cpf.length !== 11) return "";
  if (!db) return "";

  const { data, error } = await db.rpc("get_customer_email_by_cpf", {
    cpf_input: cpf
  });

  if (error) throw error;
  return normalizeEmail(data);
}

async function loadClientProfile() {
  if (!db) {
    adminLogado = false;
    clienteLogado = null;
    updateClientSessionUI();
    await updateCondominiumsMenu();
    return;
  }

  const { data: sessionData } = await db.auth.getSession();
  const user = sessionData?.session?.user;

  if (!user) {
    adminLogado = false;
    clienteLogado = null;
    updateClientSessionUI();
    await updateCondominiumsMenu();
    return;
  }

  adminLogado = normalizeEmail(user.email) === ADMIN_EMAIL;
  if (adminLogado) {
    clienteLogado = null;
    closeAccountPanel();
    closeClientAuth();
    updateClientSessionUI();
    await updateCondominiumsMenu();
    return;
  }

  const { data } = await db
    .from("customers")
    .select("id, name, email, cpf, phone, avatar_url")
    .eq("user_id", user.id)
    .maybeSingle();

  clienteLogado = data || null;
  updateClientSessionUI();
  await updateCondominiumsMenu();
}

async function ensureCustomerProfile({ name, email, cpf = "", phone = "" }) {
  if (!db || !email) return;

  const { error } = await db.rpc("upsert_customer_profile", {
    name_input: name || email,
    email_input: normalizeEmail(email),
    cpf_input: cpf ? formatCpf(cpf) : "",
    phone_input: phone || ""
  });

  if (error) throw error;
}

async function uploadCustomerAvatar(file) {
  const { data: sessionData } = await db.auth.getSession();
  const user = sessionData?.session?.user;
  if (!user) throw new Error("Usuario nao autenticado.");

  const ext = (file.name.split(".").pop() || "jpg").toLowerCase().replace(/[^a-z0-9]/g, "");
  const path = `${user.id}/profile-${Date.now()}.${ext || "jpg"}`;
  const { error } = await db.storage
    .from("avatars")
    .upload(path, file, {
      cacheControl: "3600",
      contentType: file.type,
      upsert: false
    });

  if (error) throw error;

  const { data } = db.storage.from("avatars").getPublicUrl(path);
  return data.publicUrl;
}

// ===============================
// BUSCAR PROJETOS
// ===============================
async function fetchPortfolioData() {
  if (!db) return [];

  try {
    const { data, error } = await db
      .from("projects")
      .select(`
        id,
        name,
        description,
        project_photos (
          photo_url
        )
      `)
      .order("id", { ascending: false });

    if (error) throw error;

    return data.map((projeto, index) => {
      const photos = (projeto.project_photos || [])
        .map((photo) => photo.photo_url)
        .filter(Boolean);

      return {
      id: projeto.id,
      category: projeto.description || "Projeto",
      description: projeto.description || "Projeto Edifique",
      name: projeto.name,
      photos,
      photoUrl: photos[0] || "",
      photoCount: photos.length,
      bgClass: !photos.length
        ? `p${(index % 5) + 1}`
        : "",
      bgStyle: photos[0]
        ? `style="background-image:url('${photos[0]}')"`
        : ""
      };
    });
  } catch (error) {
    console.error("Erro ao carregar projetos:", error);
    return [];
  }
}

// ===============================
// BUSCAR AVALIAÇÕES — com nome real do cliente
// ===============================
async function fetchTestimonialsData() {
  if (!db) return [];

  try {
    // Join reviews -> customers para pegar o nome real
    const { data, error } = await db
      .from("reviews")
      .select(`
        rating,
        comment,
        reviewer_name,
        reviewer_avatar_url,
        projects (
          name
        )
      `)
      .order("created_at", { ascending: false });

    if (error) throw error;

    return data.map((avaliacao) => {
      const nome = avaliacao.reviewer_name || "Cliente";

      return {
        stars: avaliacao.rating || 5,
        text: avaliacao.comment || "",
        avatar: getInitials(nome),
        avatarUrl: avaliacao.reviewer_avatar_url || "",
        name: nome,
        role: avaliacao.projects?.name
          ? `Projeto: ${avaliacao.projects.name}`
          : "Cliente Edifique"
      };
    });
  } catch (error) {
    console.error("Erro ao carregar avaliações:", error);
    return [];
  }
}

// ===============================
// RENDER PROJETOS
// ===============================
function renderPortfolio(data) {
  const grid = document.querySelector(".portfolio-grid");

  if (!grid) return;

  grid.innerHTML = data
    .map(
      (item) => `
      <div class="portfolio-item">
        <div class="portfolio-thumb">
          <div class="portfolio-bg ${item.bgClass}" ${item.bgStyle}></div>
          <div class="portfolio-overlay"></div>
          <div class="portfolio-pattern"></div>

          <div class="portfolio-info">
            <div class="portfolio-cat">${item.category}</div>
            <div class="portfolio-name">${item.name}</div>
          </div>
        </div>
      </div>
    `
    )
    .join("");
}

function renderProjectsPage(data) {
  const grid = document.querySelector(".projects-page-grid");
  const empty = document.querySelector(".projects-empty");
  const loading = document.querySelector("[data-projects-loading]");
  const count = document.querySelector("[data-projects-count]");

  if (!grid) return;

  if (loading) loading.hidden = true;
  if (count) {
    count.textContent =
      data.length === 1
        ? "1 projeto cadastrado"
        : `${data.length} projetos cadastrados`;
  }

  if (!data.length) {
    projectAlbums = [];
    grid.innerHTML = "";
    if (empty) empty.hidden = false;
    return;
  }

  if (empty) empty.hidden = true;
  projectAlbums = data;

  grid.innerHTML = data
    .map(
      (item, index) => {
        const photoLabel =
          item.photoCount === 0
            ? "Sem fotos"
            : item.photoCount === 1
              ? "1 foto"
              : `${item.photoCount} fotos`;
        const albumLabel = item.photoCount > 1 ? "Abrir álbum" : "Ver foto";

        return `
      <article class="project-card reveal" data-project-index="${index}">
        <div class="project-card-media">
          <div class="portfolio-bg ${item.bgClass}" ${
        item.photoUrl ? `style="background-image:url('${item.photoUrl}')"` : ""
      }></div>
          <div class="portfolio-overlay"></div>
          <div class="portfolio-pattern"></div>
          <div class="project-card-badge">${photoLabel}</div>
        </div>
        <div class="project-card-body">
          <div class="portfolio-cat">${escapeHtml(item.category)}</div>
          <h2>${escapeHtml(item.name)}</h2>
          <p>${escapeHtml(item.description)}</p>
          <button class="project-album-btn" type="button" data-open-album="${index}" ${
            item.photoCount ? "" : "disabled"
          }>${albumLabel}</button>
        </div>
      </article>
    `;
      }
    )
    .join("");

  setupProjectAlbums();
}

function setupProjectAlbums() {
  document.querySelectorAll("[data-open-album]").forEach((button) => {
    button.addEventListener("click", () => {
      openProjectAlbum(Number(button.dataset.openAlbum), 0);
    });
  });
}

async function renderMyCondominiumsPage() {
  const container = document.querySelector("[data-my-condominiums]");
  if (!container) return;

  container.innerHTML = '<p class="projects-loading">Carregando seus condominios...</p>';

  if (!db) {
    container.innerHTML = '<p class="projects-empty">Nao foi possivel conectar ao banco de dados.</p>';
    return;
  }

  if (adminLogado) {
    container.innerHTML = '<p class="projects-empty">A conta administrativa nao possui condominios atribuidos.</p>';
    return;
  }

  if (!clienteLogado?.id) {
    container.innerHTML = '<p class="projects-empty">Entre com sua conta para acessar seus condominios.</p>';
    showClientAuth("login");
    return;
  }

  const { data: links, error } = await db
    .from("customer_condominiums")
    .select(`
      condominium_id,
      assigned_at,
      condominiums (
        id,
        name,
        address,
        notes
      )
    `)
    .eq("customer_id", clienteLogado.id)
    .order("assigned_at", { ascending: false });

  if (error) {
    console.error("Erro ao carregar condominios do cliente:", error);
    container.innerHTML = '<p class="projects-empty">Nao foi possivel carregar seus condominios.</p>';
    return;
  }

  const condominiums = (links || [])
    .map((link) => link.condominiums || { id: link.condominium_id, name: "Condominio" })
    .filter((condo) => condo?.id);

  if (!condominiums.length) {
    container.innerHTML = '<p class="projects-empty">Nenhum condominio foi atribuido ao seu login ainda.</p>';
    return;
  }

  const html = await Promise.all(condominiums.map(async (condo) => {
    const [{ data: projects, error: projectsError }, { data: documents, error: docsError }] = await Promise.all([
      db
        .from("projects")
        .select(`
          id,
          name,
          description,
          project_photos (
            photo_url
          )
        `)
        .eq("condominium_id", condo.id)
        .order("id", { ascending: false }),
      db
        .from("condominium_documents")
        .select("id, title, document_type, file_path, file_name, uploaded_at")
        .eq("condominium_id", condo.id)
        .order("uploaded_at", { ascending: false })
    ]);

    if (projectsError) console.error("Erro ao carregar obras do condominio:", projectsError);
    if (docsError) console.error("Erro ao carregar documentos do condominio:", docsError);

    const projectsHtml = (projects || []).length
      ? (projects || []).map((project, index) => {
        const photos = (project.project_photos || []).map((photo) => photo.photo_url).filter(Boolean);
        return `
          <article class="my-condo-project">
            <div class="my-condo-project-media ${photos[0] ? "" : `p${(index % 5) + 1}`}" ${photos[0] ? `style="background-image:url('${escapeAttr(photos[0])}')"` : ""}></div>
            <div>
              <span>${photos.length === 1 ? "1 foto" : `${photos.length} fotos`}</span>
              <h3>${escapeHtml(project.name)}</h3>
              <p>${escapeHtml(project.description || "Obra do condominio")}</p>
            </div>
          </article>
        `;
      }).join("")
      : '<p class="my-condo-empty">Nenhuma obra vinculada a este condominio.</p>';

    const documentsHtml = (await Promise.all((documents || []).map(async (doc) => {
      const { data } = await db.storage
        .from("condominium-documents")
        .createSignedUrl(doc.file_path, 60 * 15);

      return `
        <article class="my-condo-doc">
          <span>${escapeHtml(doc.document_type)}</span>
          <h3>${escapeHtml(doc.title)}</h3>
          <p>${escapeHtml(doc.file_name || "Documento")}</p>
          ${data?.signedUrl ? `<a class="btn-outline" href="${escapeAttr(data.signedUrl)}" target="_blank" rel="noopener">Abrir documento</a>` : '<p class="my-condo-empty">Arquivo indisponivel.</p>'}
        </article>
      `;
    }))).join("") || '<p class="my-condo-empty">Nenhum laudo, RT ou documento registrado.</p>';

    return `
      <section class="my-condo-block reveal">
        <div class="my-condo-head">
          <div>
            <div class="section-label">Condominio</div>
            <h2 class="section-title">${escapeHtml(condo.name)}</h2>
            <p>${escapeHtml(condo.address || "Endereco nao informado")}</p>
          </div>
        </div>
        <div class="my-condo-columns">
          <div>
            <h3 class="my-condo-section-title">Obras</h3>
            <div class="my-condo-list">${projectsHtml}</div>
          </div>
          <div>
            <h3 class="my-condo-section-title">Documentos</h3>
            <div class="my-condo-list">${documentsHtml}</div>
          </div>
        </div>
      </section>
    `;
  }));

  container.innerHTML = html.join("");
  setupRevealAnimation();
}

function openProjectAlbum(projectIndex, photoIndex = 0) {
  const project = projectAlbums[projectIndex];
  if (!project?.photos?.length) return;

  let currentIndex = Math.min(Math.max(photoIndex, 0), project.photos.length - 1);
  const overlay = getProjectAlbumOverlay();

  function updateAlbumPhoto() {
    const img = overlay.querySelector(".album-photo");
    const counter = overlay.querySelector(".album-counter");
    const prev = overlay.querySelector("[data-album-prev]");
    const next = overlay.querySelector("[data-album-next]");

    img.src = project.photos[currentIndex];
    img.alt = `${project.name} - foto ${currentIndex + 1}`;
    counter.textContent = `${currentIndex + 1} / ${project.photos.length}`;
    prev.disabled = currentIndex === 0;
    next.disabled = currentIndex === project.photos.length - 1;
  }

  overlay.querySelector(".album-title").textContent = project.name;
  overlay.querySelector(".album-category").textContent =
    project.photos.length > 1 ? "Álbum do projeto" : "Foto do projeto";

  overlay.querySelector("[data-album-prev]").onclick = () => {
    if (currentIndex > 0) {
      currentIndex -= 1;
      updateAlbumPhoto();
    }
  };
  overlay.querySelector("[data-album-next]").onclick = () => {
    if (currentIndex < project.photos.length - 1) {
      currentIndex += 1;
      updateAlbumPhoto();
    }
  };

  updateAlbumPhoto();
  overlay.classList.add("open");
  overlay.setAttribute("aria-hidden", "false");
}

function closeProjectAlbum() {
  const overlay = document.querySelector(".project-album-overlay");
  if (!overlay) return;
  overlay.classList.remove("open");
  overlay.setAttribute("aria-hidden", "true");
}

function getProjectAlbumOverlay() {
  let overlay = document.querySelector(".project-album-overlay");
  if (overlay) return overlay;

  overlay = document.createElement("div");
  overlay.className = "project-album-overlay";
  overlay.setAttribute("aria-hidden", "true");
  overlay.innerHTML = `
    <div class="project-album-modal" role="dialog" aria-modal="true" aria-labelledby="albumTitle">
      <div class="project-album-head">
        <div>
          <span class="album-category"></span>
          <h2 class="album-title" id="albumTitle"></h2>
        </div>
        <button class="modal-close" type="button" data-album-close aria-label="Fechar">&times;</button>
      </div>
      <div class="album-frame">
        <img class="album-photo" src="" alt="">
      </div>
      <div class="album-controls">
        <button type="button" data-album-prev>Anterior</button>
        <span class="album-counter"></span>
        <button type="button" data-album-next>Próxima</button>
      </div>
    </div>
  `;
  document.body.appendChild(overlay);

  overlay.addEventListener("click", (event) => {
    if (event.target === overlay || event.target.closest("[data-album-close]")) {
      closeProjectAlbum();
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeProjectAlbum();
  });

  return overlay;
}

// ===============================
// RENDER AVALIAÇÕES — nome visível
// ===============================
function renderTestimonials(data) {
  const grid = document.querySelector(".testimonials-grid");

  if (!grid) return;

  grid.innerHTML = data
    .map(
      (item) => `
      <div class="testimonial-card reveal">
        <div class="testimonial-stars">
          ${"★".repeat(item.stars)}${"☆".repeat(5 - item.stars)}
        </div>

        <p class="testimonial-text">
          ${escapeHtml(item.text)}
        </p>

        <div class="testimonial-author">
          <div class="author-avatar">
            ${renderAvatarContent(item.name, item.avatarUrl, "author-avatar-img")}
          </div>

          <div>
            <div class="author-name">
              ${escapeHtml(item.name)}
            </div>

            <div class="author-role">
              ${escapeHtml(item.role)}
            </div>
          </div>
        </div>
      </div>
    `
    )
    .join("");
}

// ===============================
// ANIMAÇÕES REVEAL
// ===============================
function setupRevealAnimation() {
  const reveals = document.querySelectorAll(".reveal:not([data-observed])");

  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting) {
          e.target.classList.add("visible");
          io.unobserve(e.target);
        }
      });
    },
    {
      threshold: 0.12
    }
  );

  reveals.forEach((el) => {
    el.setAttribute("data-observed", "true");
    io.observe(el);
  });
}

// ===============================
// CONTADOR
// ===============================
function animateCount(el, target, suffix) {
  let start = 0;

  const inc = target / 60;

  const timer = setInterval(() => {
    start = Math.min(start + inc, target);

    el.textContent =
      Math.floor(start) + suffix;

    if (start >= target) {
      clearInterval(timer);
    }
  }, 25);
}

const statsIO =
  new IntersectionObserver(
    (entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting) {
          const nums =
            document.querySelectorAll(".stat-num");

          const raw =
            ["20+", "850+", "300+", "98%"];

          nums.forEach((el, i) => {
            const n = parseInt(raw[i]);

            const s =
              raw[i].replace(/\d+/, "");

            animateCount(el, n, s);
          });

          statsIO.disconnect();
        }
      });
    },
    {
      threshold: 0.5
    }
  );

const statsStrip = document.querySelector(".stats-strip");
if (statsStrip) statsIO.observe(statsStrip);

// ===============================
// NAV AO ROLAR
// ===============================
const nav =
  document.querySelector(".site-nav");

window.addEventListener(
  "scroll",
  () => {
    if (!nav) return;
    if (window.innerWidth > 900) {
      nav.style.background = ""; // Mantém o estilo CSS fixo no topo do desktop
    } else {
      nav.style.background =
        window.scrollY > 60
          ? "rgba(7,16,20,.97)"
          : "linear-gradient(to bottom, rgba(7,16,20,.92) 0%, transparent 100%)";
    }
  }
);

window.addEventListener("resize", () => {
  if (!nav) return;
  if (window.innerWidth > 900) {
    nav.style.background = "";
  } else {
    nav.style.background =
      window.scrollY > 60
        ? "rgba(7,16,20,.97)"
        : "linear-gradient(to bottom, rgba(7,16,20,.92) 0%, transparent 100%)";
  }
});

// ===============================
// INICIAR SITE
// ===============================
async function init() {
  // Garante visibilidade das partes estáticas do site logo de cara, mesmo se houver erro no BD
  setupRevealAnimation();

  try {
    await loadClientProfile();

    const portfolioData =
      await fetchPortfolioData();

    renderPortfolio(portfolioData.slice(0, 5));

    renderProjectsPage(portfolioData);

    await renderMyCondominiumsPage();

    const testimonialsData =
      document.querySelector(".testimonials-grid")
        ? await fetchTestimonialsData()
        : [];

    renderTestimonials(testimonialsData);

    setupRevealAnimation();
  } catch (error) {
    console.error(
      "Erro ao iniciar site:",
      error
    );
  }
}

init();

document.querySelectorAll(".client-auth-tab").forEach((btn) => {
  btn.addEventListener("click", () => switchClientAuthTab(btn.dataset.clientAuthTab));
});

// Botão de sessão: se logado, abre o painel de conta; se não, abre o login
document.getElementById("clientSessionBtn")?.addEventListener("click", async () => {
  if (adminLogado) {
    window.location.href = "admin.html";
    return;
  }
  if (clienteLogado) {
    showAccountPanel();
    return;
  }
  showClientAuth("login");
});

document.getElementById("clientAuthClose")?.addEventListener("click", closeClientAuth);

document.getElementById("clientAuthOverlay")?.addEventListener("click", (event) => {
  if (event.target === event.currentTarget) closeClientAuth();
});

document.getElementById("btnContinuarSemLogin")?.addEventListener("click", closeClientAuth);

document.getElementById("openReviewBtn")?.addEventListener("click", () => {
  if (!clienteLogado) {
    showClientAuth("login");
    const loginError = document.getElementById("clienteLoginError");
    if (loginError) loginError.textContent = "Faça login ou cadastre-se para enviar uma avaliação.";
    return;
  }

  showReviewForm();
});

document.getElementById("reviewClose")?.addEventListener("click", closeReviewForm);

document.getElementById("reviewOverlay")?.addEventListener("click", (event) => {
  if (event.target === event.currentTarget) closeReviewForm();
});

document.getElementById("cliente-cad-cpf")?.addEventListener("input", function () {
  this.value = formatCpf(this.value);
});

document.getElementById("cliente-login-id")?.addEventListener("input", function () {
  if (/^\d[\d.\-]*$/.test(this.value)) this.value = formatCpf(this.value);
});

document.getElementById("cliente-cad-phone")?.addEventListener("input", function () {
  this.value = formatPhone(this.value);
});

function getClientSignupErrorMessage(error) {
  const message = `${error?.message || ""} ${error?.code || ""}`.toLowerCase();

  if (message.includes("weak_password") || message.includes("password should be at least 6")) {
    return "A senha precisa ter pelo menos 6 caracteres.";
  }

  if (
    message.includes("already") ||
    message.includes("registered") ||
    message.includes("duplicate") ||
    message.includes("cpf") ||
    message.includes("23505")
  ) {
    return "CPF ou e-mail ja cadastrado.";
  }

  if (message.includes("database") || message.includes("saving new user")) {
    return "Nao foi possivel salvar o cadastro no banco. Tente outro CPF/e-mail ou fale com o administrador.";
  }

  if (message.includes("rate") || message.includes("too many")) {
    return "Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.";
  }

  return error?.message
    ? `Nao foi possivel cadastrar: ${error.message}`
    : "Nao foi possivel cadastrar. Verifique CPF, e-mail e WhatsApp.";
}

document.getElementById("formClienteLogin")?.addEventListener("submit", async function (event) {
  event.preventDefault();

  const credential = document.getElementById("cliente-login-id").value.trim();
  const password = document.getElementById("cliente-login-pass").value;
  const errorBox = document.getElementById("clienteLoginError");
  const submitButton = this.querySelector('button[type="submit"]');
  errorBox.textContent = "";

  if (!credential || !password) {
    errorBox.textContent = "Informe e-mail/CPF e senha.";
    return;
  }

  if (submitButton) {
    submitButton.disabled = true;
    submitButton.textContent = "Entrando...";
  }

  try {
    if (!db) throw new Error("Banco de dados offline.");

    const email = await resolveEmailFromCredential(credential);
    if (!email) {
      errorBox.textContent = "Cliente não encontrado.";
      return;
    }

    const { error } = await db.auth.signInWithPassword({ email, password });
    if (error) {
      console.error("Erro Supabase no login do cliente:", error);
      errorBox.textContent = "Cliente ou senha inválidos.";
      return;
    }

    await loadClientProfile();
    if (!clienteLogado?.id) {
      await db.auth.signOut();
      clienteLogado = null;
      updateClientSessionUI();
      await updateCondominiumsMenu();
      errorBox.textContent = "Cadastro de cliente nÃ£o encontrado. Faça seu cadastro antes de entrar.";
      return;
    }
    closeClientAuth();
    await renderMyCondominiumsPage();
  } catch (error) {
    console.error("Erro no login do cliente:", error);
    errorBox.textContent = "Não foi possível entrar agora.";
  } finally {
    if (submitButton) {
      submitButton.disabled = false;
      submitButton.textContent = "Entrar como cliente";
    }
  }
});

document.getElementById("formClienteCadastro")?.addEventListener("submit", async function (event) {
  event.preventDefault();

  const name = document.getElementById("cliente-cad-nome").value.trim();
  const cpf = normalizeCpf(document.getElementById("cliente-cad-cpf").value);
  const phone = document.getElementById("cliente-cad-phone").value.trim();
  const email = normalizeEmail(document.getElementById("cliente-cad-email").value);
  const password = document.getElementById("cliente-cad-pass").value;
  const errorBox = document.getElementById("clienteCadastroError");
  const submitButton = this.querySelector('button[type="submit"]');
  errorBox.textContent = "";

  if (!name || cpf.length !== 11 || !phone || !/\S+@\S+\.\S+/.test(email) || !password) {
    errorBox.textContent = "Preencha nome, CPF, WhatsApp, e-mail e senha válidos.";
    return;
  }

  if (password.length < 6) {
    errorBox.textContent = "A senha precisa ter pelo menos 6 caracteres.";
    return;
  }

  if (submitButton) {
    submitButton.disabled = true;
    submitButton.textContent = "Cadastrando...";
  }

  try {
    if (!db) throw new Error("Banco de dados offline.");

    const { data, error } = await db.auth.signUp({
      email,
      password,
      options: {
        data: {
          name,
          cpf: formatCpf(cpf),
          phone
        }
      }
    });

    if (error) {
      errorBox.textContent = getClientSignupErrorMessage(error);
      return;
    }

    const { error: loginError } = data?.session
      ? { error: null }
      : await db.auth.signInWithPassword({ email, password });
    if (loginError) {
      errorBox.textContent = "Cadastro concluído. Faça login para continuar.";
      switchClientAuthTab("login");
      return;
    }

    await ensureCustomerProfile({
      name,
      email,
      cpf,
      phone
    });
    await loadClientProfile();
    this.reset();
    closeClientAuth();
  } catch (error) {
    console.error("Erro no cadastro do cliente:", error);
    errorBox.textContent = "Não foi possível cadastrar agora.";
  } finally {
    if (submitButton) {
      submitButton.disabled = false;
      submitButton.textContent = "Cadastrar e entrar";
    }
  }
});

document.getElementById("reviewForm")?.addEventListener("submit", async function (event) {
  event.preventDefault();

  const rating = parseInt(document.getElementById("reviewRating").value, 10);
  const comment = document.getElementById("reviewComment").value.trim();
  const errorBox = document.getElementById("reviewError");
  errorBox.textContent = "";

  if (!clienteLogado) {
    closeReviewForm();
    showClientAuth("login");
    return;
  }

  if (!rating || rating < 1 || rating > 5 || !comment) {
    errorBox.textContent = "Informe uma nota e escreva seu depoimento.";
    return;
  }

  try {
    if (!clienteLogado.id) {
      await loadClientProfile();
    }

    if (!clienteLogado?.id) {
      errorBox.textContent = "Nao foi possivel localizar seu cadastro.";
      return;
    }

    const { error } = await db.from("reviews").insert([
      {
        customer_id: clienteLogado.id,
        rating,
        comment,
        reviewer_name: clienteLogado.name || "Cliente",
        reviewer_avatar_url: clienteLogado.avatar_url || null
      }
    ]);

    if (error) throw error;

    this.reset();
    closeReviewForm();

    const testimonialsData = await fetchTestimonialsData();
    renderTestimonials(testimonialsData);
    setupRevealAnimation();
  } catch (error) {
    console.error("Erro ao enviar avaliação:", error);
    errorBox.textContent = "Não foi possível enviar sua avaliação agora.";
  }
});

if (db) {
  db.auth.onAuthStateChange(async () => {
    await loadClientProfile();
    await renderMyCondominiumsPage();
  });
}
