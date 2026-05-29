const SUPABASE_URL = "https://uimjqymytxqvvwrojcgg.supabase.co";

const SUPABASE_ANON_KEY =
  "sb_publishable_k-VnTcGnw9yTPXteKozg3w_z4fi_uf8";

const db = supabase.createClient(
  SUPABASE_URL,
  SUPABASE_ANON_KEY
);

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
        customers (
          name
        ),
        projects (
          name
        )
      `)
      .order("created_at", { ascending: false });

    if (error) throw error;

    return data.map((avaliacao) => {
      const nome = avaliacao.customers?.name || "Cliente";

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