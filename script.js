const SUPABASE_URL = "https://uimjqymytxqvvwrojcgg.supabase.co";

const SUPABASE_ANON_KEY =
  "sb_publishable_k-VnTcGnw9yTPXteKozg3w_z4fi_uf8";

const db = supabase.createClient(
  SUPABASE_URL,
  SUPABASE_ANON_KEY
);

let clienteLogado = null;

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

function updateClientSessionUI() {
  const btn = document.getElementById("clientSessionBtn");
  if (!btn) return;

  const label = btn.querySelector("span");
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

async function resolveEmailFromCredential(credential) {
  if (credential.includes("@")) return normalizeEmail(credential);

  const cpf = normalizeCpf(credential);
  if (cpf.length !== 11) return "";

  const { data, error } = await db.rpc("get_customer_email_by_cpf", {
    cpf_input: cpf
  });

  if (error) throw error;
  return normalizeEmail(data);
}

async function loadClientProfile() {
  const { data: sessionData } = await db.auth.getSession();
  const user = sessionData?.session?.user;

  if (!user) {
    clienteLogado = null;
    updateClientSessionUI();
    return;
  }

  const { data } = await db
    .from("customers")
    .select("name, email, cpf, phone")
    .eq("user_id", user.id)
    .maybeSingle();

  clienteLogado = data || {
    name: user.user_metadata?.name || user.email,
    email: user.email
  };
  updateClientSessionUI();
}

// ===============================
// BUSCAR PROJETOS
// ===============================
async function fetchPortfolioData() {
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

    return data.map((projeto, index) => ({
      category: projeto.description || "Projeto",
      name: projeto.name,
      bgClass: !projeto.project_photos?.length
        ? `p${(index % 5) + 1}`
        : "",
      bgStyle: projeto.project_photos?.[0]?.photo_url
        ? `style="background-image:url('${projeto.project_photos[0].photo_url}')"`
        : ""
    }));
  } catch (error) {
    console.error("Erro ao carregar projetos:", error);
    return [];
  }
}

// ===============================
// BUSCAR AVALIAÇÕES
// ===============================
async function fetchTestimonialsData() {
  try {
    const { data, error } = await db
      .from("reviews")
      .select(`
        rating,
        comment,
        projects (
          name
        )
      `)
      .order("created_at", { ascending: false });

    if (error) throw error;

    return data.map((avaliacao) => {
      const nome = "Cliente";

      const iniciais = nome
        .split(" ")
        .map((n) => n[0])
        .join("")
        .substring(0, 2)
        .toUpperCase();

      return {
        stars: avaliacao.rating || 5,
        text: avaliacao.comment || "",
        avatar: iniciais,
        name: nome,
        role: avaliacao.projects?.name
          ? `Projeto: ${avaliacao.projects.name}`
          : "Cliente"
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

// ===============================
// RENDER AVALIAÇÕES
// ===============================
function renderTestimonials(data) {
  const grid = document.querySelector(".testimonials-grid");

  if (!grid) return;

  grid.innerHTML = data
    .map(
      (item) => `
      <div class="testimonial-card reveal">
        <div class="testimonial-stars">
          ${"★".repeat(item.stars)}
        </div>

        <p class="testimonial-text">
          ${item.text}
        </p>

        <div class="testimonial-author">
          <div class="author-avatar">
            ${item.avatar}
          </div>

          <div>
            <div class="author-name">
              ${item.name}
            </div>

            <div class="author-role">
              ${item.role}
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
  const reveals = document.querySelectorAll(".reveal");

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

  reveals.forEach((el) => io.observe(el));
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

statsIO.observe(
  document.querySelector(".stats-strip")
);

// ===============================
// NAV AO ROLAR
// ===============================
const nav =
  document.querySelector("nav");

window.addEventListener(
  "scroll",
  () => {
    nav.style.background =
      window.scrollY > 60
        ? "rgba(20,18,16,.97)"
        : "linear-gradient(to bottom, rgba(20,18,16,.92) 0%, transparent 100%)";
  }
);

// ===============================
// INICIAR SITE
// ===============================
async function init() {
  try {
    await loadClientProfile();

    const portfolioData =
      await fetchPortfolioData();

    const testimonialsData =
      await fetchTestimonialsData();

    renderPortfolio(portfolioData);

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

document.getElementById("clientSessionBtn")?.addEventListener("click", async () => {
  if (clienteLogado) {
    await db.auth.signOut();
    clienteLogado = null;
    updateClientSessionUI();
    showClientAuth("login");
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

  if (message.includes("weak_password") || message.includes("password") || message.includes("senha")) {
    return "Senha recusada pelo Supabase Auth. O site nao limita tamanho de senha; ajuste as regras de senha no painel Supabase ou tente uma senha diferente.";
  }

  if (message.includes("already") || message.includes("registered") || message.includes("duplicate")) {
    return "CPF ou e-mail ja cadastrado.";
  }

  return "Nao foi possivel cadastrar. Verifique CPF, e-mail e WhatsApp.";
}

document.getElementById("formClienteLogin")?.addEventListener("submit", async function (event) {
  event.preventDefault();

  const credential = document.getElementById("cliente-login-id").value.trim();
  const password = document.getElementById("cliente-login-pass").value;
  const errorBox = document.getElementById("clienteLoginError");
  errorBox.textContent = "";

  if (!credential || !password) {
    errorBox.textContent = "Informe e-mail/CPF e senha.";
    return;
  }

  try {
    const email = await resolveEmailFromCredential(credential);
    if (!email) {
      errorBox.textContent = "Cliente não encontrado.";
      return;
    }

    const { error } = await db.auth.signInWithPassword({ email, password });
    if (error) {
      errorBox.textContent = "Cliente ou senha inválidos.";
      return;
    }

    await loadClientProfile();
    closeClientAuth();
    window.location.href = "index.html";
  } catch (error) {
    console.error("Erro no login do cliente:", error);
    errorBox.textContent = "Não foi possível entrar agora.";
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
  errorBox.textContent = "";

  if (!name || cpf.length !== 11 || !phone || !/\S+@\S+\.\S+/.test(email) || !password) {
    errorBox.textContent = "Preencha nome, CPF, WhatsApp, e-mail e senha válidos.";
    return;
  }

  try {
    const { error } = await db.auth.signUp({
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

    const { error: loginError } = await db.auth.signInWithPassword({ email, password });
    if (loginError) {
      errorBox.textContent = "Cadastro concluído. Faça login para continuar.";
      switchClientAuthTab("login");
      return;
    }

    await loadClientProfile();
    this.reset();
    closeClientAuth();
    window.location.href = "index.html";
  } catch (error) {
    console.error("Erro no cadastro do cliente:", error);
    errorBox.textContent = "Não foi possível cadastrar agora.";
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
    const { error } = await db.from("reviews").insert([
      { rating, comment }
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

db.auth.onAuthStateChange(() => {
  loadClientProfile();
});
