// ============================================================
// EDIFIQUE CONSTRUÇÕES — SISTEMA DE AUTENTICAÇÃO + ADMIN PANEL
// ============================================================
// Para conectar ao Supabase real:
// 1. Crie um projeto em supabase.com
// 2. Substitua SUPABASE_URL e SUPABASE_ANON_KEY
// 3. Execute o SQL em db_setup.sql no SQL Editor do Supabase
// ============================================================

const SUPABASE_URL = 'SUA_URL_SUPABASE_AQUI';
const SUPABASE_ANON_KEY = 'SUA_ANON_KEY_AQUI';

// Detecta se Supabase está configurado
const SUPABASE_CONFIGURED = !SUPABASE_URL.includes('SUA_URL');

// ── BANCO LOCAL (fallback para desenvolvimento) ──
const LOCAL_DB = {
  users: JSON.parse(localStorage.getItem('edifique_users') || '[]'),
  portfolio: JSON.parse(localStorage.getItem('edifique_portfolio') || JSON.stringify([
    { id:1, name:'Condomínio Residencial Atlântico', category:'Recuperação Estrutural', bgClass:'p1', year:'2024', location:'Balneário Camboriú', desc:'Reforço de 12 pilares e tratamento de fissuras em fachada.' },
    { id:2, name:'Ed. Comercial Serra Verde', category:'Impermeabilização', bgClass:'p2', year:'2023', location:'Florianópolis', desc:'Impermeabilização de coberturas e áreas técnicas.' },
    { id:3, name:'Residencial Costa Brava', category:'Pintura e Fachada', bgClass:'p3', year:'2024', location:'Itajaí', desc:'Revitalização completa de fachada com tinta elastomérica.' },
    { id:4, name:'Condomínio Vista Mar', category:'Manutenção Preventiva', bgClass:'p4', year:'2023', location:'Joinville', desc:'Plano anual de manutenção predial preventiva.' },
    { id:5, name:'Residencial Pedra Branca', category:'Estrutura e Concreto', bgClass:'p5', year:'2024', location:'Palhoça', desc:'Recuperação de laje e reforço estrutural.' },
  ])),
  testimonials: JSON.parse(localStorage.getItem('edifique_testimonials') || JSON.stringify([
    { id:1, name:'Carlos Mendonça', role:'Síndico — Ed. Atlântico', stars:5, text:'A Edifique superou todas as expectativas. Profissionalismo exemplar do início ao fim, com relatórios detalhados e prazo cumprido rigorosamente.', avatar:'CM', status:'approved' },
    { id:2, name:'Ana Paula Ferreira', role:'Administradora — Residencial Serra', stars:5, text:'Contratamos para recuperação estrutural e ficamos impressionados com a qualidade técnica. A equipe identificou problemas que outros não viram.', avatar:'AP', status:'approved' },
    { id:3, name:'Roberto Silveira', role:'Síndico — Condomínio Vista Mar', stars:5, text:'Parceria de anos com excelentes resultados. A manutenção preventiva reduziu nossos custos emergenciais em mais de 60%.', avatar:'RS', status:'approved' },
  ])),
  services: JSON.parse(localStorage.getItem('edifique_services') || JSON.stringify([
    { id:1, num:'01', title:'Estrutura e Concreto', desc:'Reforço estrutural, tratamento de fissuras, corrosão de armaduras e recuperação de pilares e vigas.' },
    { id:2, num:'02', title:'Manutenção Preventiva', desc:'Planos anuais de manutenção programada reduzindo custos emergenciais e prolongando a vida útil do edifício.' },
    { id:3, num:'03', title:'Inspeção e Laudos', desc:'Laudos técnicos, vistorias prediais e relatórios de inspeção por engenheiros registrados no CREA.' },
  ])),
  save() {
    localStorage.setItem('edifique_users', JSON.stringify(this.users));
    localStorage.setItem('edifique_portfolio', JSON.stringify(this.portfolio));
    localStorage.setItem('edifique_testimonials', JSON.stringify(this.testimonials));
    localStorage.setItem('edifique_services', JSON.stringify(this.services));
  }
};

// ── ADMIN PADRÃO (criado na primeira vez) ──
function initAdminUser() {
  const existingAdmin = LOCAL_DB.users.find(u => u.role === 'admin');
  if (!existingAdmin) {
    LOCAL_DB.users.push({
      id: 'admin_001',
      name: 'Administrador Edifique',
      email: 'admin@edifique.com.br',
      password: 'Edifique@2026',
      role: 'admin',
      createdAt: new Date().toISOString(),
      approved: true
    });
    LOCAL_DB.save();
    console.log('✅ Admin criado: admin@edifique.com.br / Edifique@2026');
  }
}

// ── SESSION ──
let currentUser = JSON.parse(sessionStorage.getItem('edifique_session') || 'null');

function setSession(user) {
  currentUser = user;
  sessionStorage.setItem('edifique_session', JSON.stringify(user));
}
function clearSession() {
  currentUser = null;
  sessionStorage.removeItem('edifique_session');
}

// ── AUTH API ──
async function authLogin(email, password) {
  const user = LOCAL_DB.users.find(u => u.email === email && u.password === password && u.approved);
  if (!user) throw new Error('Email ou senha incorretos, ou cadastro pendente de aprovação.');
  const { password: _, ...safeUser } = user;
  setSession(safeUser);
  return safeUser;
}

async function authRegister(name, email, password) {
  if (LOCAL_DB.users.find(u => u.email === email)) throw new Error('Este e-mail já está cadastrado.');
  const user = {
    id: 'user_' + Date.now(),
    name, email, password,
    role: 'client',
    createdAt: new Date().toISOString(),
    approved: false
  };
  LOCAL_DB.users.push(user);
  LOCAL_DB.save();
  return user;
}

// ── DATA API ──
const API = {
  portfolio: {
    list: () => LOCAL_DB.portfolio,
    add(item) { 
      item.id = Date.now(); 
      LOCAL_DB.portfolio.push(item); 
      LOCAL_DB.save(); 
      return item; 
    },
    remove(id) { 
      LOCAL_DB.portfolio = LOCAL_DB.portfolio.filter(i => i.id !== id); 
      LOCAL_DB.save(); 
    },
    update(id, data) {
      const idx = LOCAL_DB.portfolio.findIndex(i => i.id === id);
      if (idx !== -1) { LOCAL_DB.portfolio[idx] = { ...LOCAL_DB.portfolio[idx], ...data }; LOCAL_DB.save(); }
    }
  },
  testimonials: {
    list: (onlyApproved = true) => onlyApproved 
      ? LOCAL_DB.testimonials.filter(t => t.status === 'approved')
      : LOCAL_DB.testimonials,
    add(item) { 
      item.id = Date.now(); 
      item.status = 'pending'; 
      LOCAL_DB.testimonials.push(item); 
      LOCAL_DB.save(); 
      return item; 
    },
    approve(id) {
      const t = LOCAL_DB.testimonials.find(t => t.id === id);
      if (t) { t.status = 'approved'; LOCAL_DB.save(); }
    },
    reject(id) {
      LOCAL_DB.testimonials = LOCAL_DB.testimonials.filter(t => t.id !== id);
      LOCAL_DB.save();
    }
  },
  services: {
    list: () => LOCAL_DB.services,
    add(item) { item.id = Date.now(); LOCAL_DB.services.push(item); LOCAL_DB.save(); return item; },
    remove(id) { LOCAL_DB.services = LOCAL_DB.services.filter(i => i.id !== id); LOCAL_DB.save(); },
    update(id, data) {
      const idx = LOCAL_DB.services.findIndex(i => i.id === id);
      if (idx !== -1) { LOCAL_DB.services[idx] = { ...LOCAL_DB.services[idx], ...data }; LOCAL_DB.save(); }
    }
  },
  users: {
    list: () => LOCAL_DB.users.map(u => { const { password: _, ...s } = u; return s; }),
    approve(id) {
      const u = LOCAL_DB.users.find(u => u.id === id);
      if (u) { u.approved = true; LOCAL_DB.save(); }
    },
    remove(id) {
      LOCAL_DB.users = LOCAL_DB.users.filter(u => u.id !== id);
      LOCAL_DB.save();
    }
  }
};

initAdminUser();
